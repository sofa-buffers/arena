# C#: SofaBuffers vs Google.Protobuf — bottleneck analysis & optimization results

**Date:** 2026-07-04 · **Host:** 6-core VPS (VM + docker), .NET 9.0.315, workstation GC
(`DOTNET_GCgen0size=0x4000000`, symmetric to both impls per `bench.sh`)
**Scope:** `corelib-cs` runtime + `sofabgen` C# backend, measured with the arena
`csharp` maxspeed target (2 M encode+decode iterations, canonical message,
434 B sofab wire / 494 B protobuf wire). Companion to `JAVA-OPTIMIZATION.md`
(same method, same wire-size-normalization insight).

---

## TL;DR

The C# port was the family's weakest maxspeed target (0.91x vs protobuf). Its
**decoder** already had good fast paths — but its **encoder was per-byte
everywhere**, and the generated code bridged every array through LINQ-ish
temporaries. After porting the Java-proven fixes plus C#-specific ones:

| metric (median, interleaved A/B, 7 rounds, 2 M iters) | before | after |
|---|---|---|
| sofab round-trip cpu | 8.360 s | **5.090 s** (−39.1%) |
| sofab throughput | 103.8 MB/s | **170.5 MB/s** (+64.3%) |
| protobuf throughput (same rounds, control) | 110.8 MB/s | 110.8 MB/s |
| per-message speed vs protobuf | ~1.07x faster | **1.75x faster** |
| arena "speed advantage" (MB/s ratio) | **0.91x** | **1.54x — sofab wins big** |

Official arena methodology (`LANGS=csharp RUNS=5 ./scripts/run_benchmark.sh
--no-setup`, best-of-5): **sofab 171.01 MB/s vs protobuf 110.32 MB/s → 1.55x**
(row updated in `results/RESULTS.txt`). Even against protobuf's *historical* best
row (132.19 MB/s, recorded on a quieter run of this VPS), sofab now wins 1.29x.

Correctness: wire bytes **sha-identical** across all baseline and optimized runs
(`e17334…e29d9d`), all **455 corelib-cs tests** (incl. wire-conformance vectors)
pass, all generator Go tests pass (csharp golden regenerated).

## 1. Architecture comparison

| aspect | SofaBuffers (corelib-cs + gen) | Google.Protobuf 3.28.3 |
|---|---|---|
| message model | mutable POJO | immutable-ish message + `MessageParser` |
| encode | `OStream` into caller buffer | `CalculateSize()` → exact `byte[]` → `WriteTo` |
| size memoization | none needed (scratch buffer) | **none** — C# protobuf recomputes `CalculateSize()` every `ToByteArray()` (unlike protobuf-java) |
| decode | `IStream` fast pointer path → `IVisitor` push callbacks | `CodedInputStream` tag loop into `RepeatedField` |
| string decode | zero-copy slice → `Encoding.UTF8.GetString` in visitor | same class of cost |

## 2. Bottlenecks found

The Java investigation (see `JAVA-OPTIMIZATION.md` §2) predicted most of them;
code inspection confirmed which ones the C# port shared:

**corelib-cs encoder (the dominant cost — shared Java gaps, but worse):**
- `PushByte` per output byte with a flush branch + array bounds check —
  *everything* went through it: `PushRaw` copied string/blob payloads
  **byte-by-byte** (no `Array.Copy`), floats were written as 4/8 `PushByte`
  calls, and `WriteVarint` had no single-byte fast case and no hoisted-cursor
  bulk path (`OStream.cs:141-182` pre-change).
- `WriteString` allocated a throwaway `byte[]` via `Encoding.UTF8.GetBytes(text)`
  per call, then re-copied it per-byte through `PushRaw` (~6 strings/message).
- All 8 integer array overloads looped `WriteVarint` per element (no inline
  cursor loop at any width — Java at least had 32/64-bit fast loops).

**corelib-cs decoder (already good, one shared gap):**
- `ReadVarint` did a `while (p < end)` per-byte bounds check for every varint
  byte (header, scalar, count, element) — the same gap the Java decoder had.

**generated code (`sofabgen` csharp backend):**
- `Encode()`: fresh zeroed `new byte[MaxSize=1011]` + exact-size copy per call
  (Java twin).
- Native scalar arrays were `List<T>` fields: **10 `.ToArray()` allocations per
  encode** to bridge into the corelib array writers, and Add-growth per decode.
- Per-decode eager `List<byte> acc` + `Stack<int>` in the visitor; LINQ
  `SequenceEqual(x ?? Array.Empty<byte>(), Array.Empty<byte>())` blob omit check.

## 3. What was changed

### corelib-cs (`src/SofaBuffers/`, +319/−56)

`OStream.cs`
1. `WriteVarint`: 10-byte-room fast path with local cursor, single-byte fast
   case; old per-byte loop kept as `WriteVarintSlow` for the buffer tail.
2. `PushRaw`: bulk `Array.Copy` up to each buffer boundary (was per-byte).
3. `WriteString`: `Encoding.UTF8.GetByteCount` (vectorized) for the header, then
   `Encoding.UTF8.GetBytes(text, …, _buffer, _offset)` **straight into the
   output buffer** when it has room — zero temp allocation; temp+`PushRaw`
   fallback only for buffer-spanning writes.
4. `PutLe32`/`PutLe64` helpers via `BinaryPrimitives.Write*LittleEndian`
   (single store instead of 4/8 `PushByte`s); used by `WriteFp32/64` and both
   float array writers.
5. All 8 integer array overloads: hoisted-cursor inline varint loops
   (`b[p++] = (byte)(v | 0x80)` protobuf-style), `WriteVarintSlow` spill.

`IStream.cs`
6. `ReadVarint`: when ≥10 bytes remain, decode with no per-byte end check
   (continuation via `(sbyte)` sign bit), identical overflow semantics; the
   checked loop remains as `ReadVarintChecked` for the buffer tail — split-feed
   streaming behavior unchanged. One fix covers header/scalar/count/element
   sites since `ReadVarint` is the shared primitive.
7. `ReadInt32Le`/`ReadInt64Le` via `BinaryPrimitives` (was per-byte OR-shift).

### sofabgen C# backend (`generator/generators/csharp/`, +125/−21)

8. **Primitive arrays**: native numeric/fp array fields now lower to `T[]`
   (`byte[]`, `ulong[]`, `float[]`, …) instead of `List<T>` — mirroring the
   Java backend's design. Marshal passes them **directly** to the OStream
   overloads (no `.ToArray()`); the visitor allocates the exact-size array in
   `ArrayBegin(count)` and fills by index (`ai++`). Bool/enum/bitfield arrays
   and nested-array rows stay `List<T>` (value-converted element-wise).
   *Note: this changes the generated public field type — a sofabgen minor bump.*
9. `Encode()`: `[ThreadStatic]` scratch buffer instead of a fresh zeroed
   worst-case array per call (same re-entrancy caveat as Java, documented in
   the emitted comment).
10. Blob omit with empty default: `x != null && x.Length != 0` (no LINQ).
11. Visitor: lazy `List<byte> acc` (split payloads only), unboxed `int[]`
    scope stack replacing `Stack<int>`.

The arena driver `languages/csharp/sofab/Bench.cs` was updated for the array
field types (construction only — outside the timed region; loop untouched).
Nothing about the wire format changed: every run emits the canonical 434-byte
wire with the reference sha.

## 4. Verification

- `corelib-cs`: `dotnet test SofaBuffers.sln -c Release` → **455/455 pass**.
- `generator`: `go test ./...` → all pass; csharp golden regenerated (no other
  language backend drifted).
- Arena self-check (round-trip byte identity + sha gate): pass, before and after.
- A/B method: baseline binaries rebuilt from clean git state (`git stash` of
  corelib-cs + generator + arena), optimized binaries from the working tree;
  7 interleaved rounds base → opt → protobuf at 2 M iters; medians. protobuf
  as per-round control (VPS single runs swing ±8%).
- dotnet-trace (EventPipe SampleProfiler) was used for spot confirmation, but
  leaf attribution in this container collapses optimized frames into
  `UNMANAGED_CODE_TIME`; the analysis above rests on code inspection guided by
  the Java profile plus the measured A/B deltas per change group.

## 5. Plan to land these optimizations

| repo | change | risk |
|---|---|---|
| `corelib-cs` | `OStream.cs`, `IStream.cs` (items 1–7) | low — conformance-vector-gated; no API change |
| `generator` | `generators/csharp/{backend,helpers,visitor}.go` + golden (items 8–11) | **medium** — item 8 changes generated field types `List<T>` → `T[]` (breaking for consumers that call `.Add`/`.Count` on those fields) |
| `arena` | regenerated `languages/csharp/sofab/gen/Message.cs`, updated `Bench.cs` fill, `results/RESULTS.txt` csharp row | derived artifacts |

Suggested landing order:
1. **PR 1 — corelib-cs hot paths** (items 1–7). Pure runtime win for all
   existing generated code; ship first. (Encoder alone was worth most of the
   3.3 s/2M-iter improvement.)
2. **PR 2 — generator C# backend** (items 9–11 only) as a patch release:
   scratch buffer + lazy visitor state + omit-check cleanups are non-breaking.
3. **PR 3 — primitive arrays** (item 8) as a **minor version bump** with a
   changelog note (generated field type change), landing together with the
   Java backend's identical design already in place — this aligns C# with
   Java/C++/Rust/Go, which all use native arrays for numeric array fields.
4. **Arena refresh** on the reference machine after merges (other rows in
   RESULTS.txt still show the previous full run / pre-v0.11.0 436 B wire).

### Remaining headroom (future work)

- Per-element `IVisitor` interface dispatch on decode — a generic
  `Feed<TVisitor>(…) where TVisitor : IVisitor` would let the JIT devirtualize
  and inline the callbacks (C# can do this better than Java); family-wide API
  design decision.
- `FastField` loop fusion in `Feed` (same idea as the Java plan).
- `Encoding.UTF8.GetString` per string decode and `new byte[total]` per blob
  decode are inherent to materializing a POJO — protobuf pays the same.

### Reproduce

```bash
BENCH_ITERS=2000000 <scratchpad>/ab-cs.sh 7        # interleaved A/B (binaries preserved)
cd /workspace/arena && LANGS=csharp RUNS=5 ./scripts/run_benchmark.sh --no-setup
```
