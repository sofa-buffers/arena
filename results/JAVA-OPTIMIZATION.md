# Java: SofaBuffers vs protobuf-java — bottleneck analysis & optimization results

**Date:** 2026-07-04 · **Host:** 6-core VPS (VM + docker), OpenJDK 21.0.11, ParallelGC
**Scope:** `corelib-java` runtime + `sofabgen` Java backend (generated code), measured
with the arena `java` maxspeed target (2 M encode+decode iterations, canonical
`schema/state.json` message, 434 B sofab wire / 494 B protobuf wire).

---

## TL;DR

The 0.84x speed deficit against protobuf-java was an *implementation* gap, not a
wire-format gap — exactly as suspected. After optimizing the corelib hot paths and
the generated-code allocation profile:

| metric (median, interleaved A/B, 2 M iters) | before | after |
|---|---|---|
| sofab round-trip cpu | 4.908 s | **4.263 s** (−13.1%) |
| sofab throughput | 176.9 MB/s | **203.6 MB/s** (+15.1%) |
| protobuf throughput (same rounds, control) | 194.0 MB/s | 194.0 MB/s |
| per-message speed vs protobuf | ~1.04x faster | **1.195x faster** |
| arena "speed advantage" (MB/s ratio) | **0.84x** | **1.05x — sofab wins** |

Official arena methodology (`LANGS=java RUNS=5 ./scripts/run_benchmark.sh --no-setup`,
best-of-5): **sofab 213.45 MB/s vs protobuf 203.24 MB/s → 1.05x** (row updated in
`results/RESULTS.txt`).

Correctness: wire bytes stayed **sha-identical**
(`e17334…e29d9d`), all **614 corelib-java tests** (incl. 533 wire-conformance
vectors) pass, all generator Go tests pass (goldens regenerated).

An important measurement insight: the arena ranks by MB/s **normalized to each
impl's own wire size**. SofaBuffers' wire is 1.14x smaller (434 B vs 494 B), so to
*tie* in MB/s it must be 1.14x *faster per message*. Baseline sofab was already
~4% faster per message than protobuf — the 0.84x figure hid that. It now must and
does clear the 1.14x bar (1.195x).

---

## 1. How the two implementations compare architecturally

| aspect | SofaBuffers (corelib-java + gen) | protobuf-java 3.21.12 |
|---|---|---|
| message model | mutable POJO, primitive `long`/`float[]`… fields | immutable message + Builder |
| encode | marshal into caller buffer via `OStream` (streaming, `FlushSink`) | `getSerializedSize()` (memoized) → exact `byte[]` → `CodedOutputStream` |
| size pass | none (worst-case `MAX_SIZE` buffer) | full size pass, **memoized on the reused immutable message** |
| decode | push-parser: `IStream` fast pointer path → `Visitor` callbacks, POJO filled directly, exact-size arrays | pull-parser: `CodedInputStream` tag loop → Builder + growable `IntList`/`LongList` → `buildPartial()` |
| string decode | `new String(buf, off, len, UTF_8)` from input slice | same |
| unsafe usage | none | `Utf8$UnsafeProcessor`, `Unsafe.putByte` on encode |

Structural advantages already on sofab's side: no Builder layer, no growable-list
reallocation on decode, exact-size arrays, no size pre-pass. Structural advantages
on protobuf's side: single exact-size allocation per encode, memoized size, and
Unsafe-based UTF-8. The benchmark drivers are symmetric (same warm-up, same timed
loop, same JVM flags).

## 2. Bottlenecks found (async-profiler, itimer 1 ms, main thread only)

Baseline profile — encode 36.7% / decode 59.1% of round-trip:

- **Encode / strings ≈ 17%:** `writeUtf8` pushed *every* UTF-8 byte through
  `pushByte` (a bounds check + flush branch per byte), plus a second full
  `charAt` walk in `utf8Length`. ~90 payload bytes of strings per message.
- **Encode / varints ≈ 44%:** `writeVarint` loop entry even for 1-byte values
  (most field headers are 1 byte); 8/16-bit array overloads called
  `writeVarint` per element instead of the hoisted-cursor loop the 32/64-bit
  overloads have.
- **Encode / generated:** `new byte[MAX_SIZE=1011]` (zeroed!) + `Arrays.copyOf`
  per `encode()`; `Arrays.equals(bytes_field, new byte[0])` allocated per call;
  `Objects.equals(str, "")` static-call indirection.
- **Decode / varint decode ≈ 44% :** `fastField` header/scalar and
  `fastVarintArray` element loops did a `q < end` bounds check **per byte**
  (the encoder already had the "≥10 bytes room → no per-byte checks" trick;
  the decoder didn't).
- **Decode / generated:** per-decode allocations that are dead weight in the
  common single-feed case: eager `ByteArrayOutputStream` (+ its `byte[32]`),
  ~12 fresh zero-length arrays from field initializers.

## 3. What was changed

### corelib-java (`src/main/java/org/sofabuffers/sofab/`, +266/−82)

`OStream.java`
1. `writeVarint`: single-byte fast case before the emit loop.
2. `writeString`/`writeUtf8(s, n)`: the measured byte length `n` now gates an
   exact-room bulk path — ASCII run loop + multi-byte tail written with a local
   cursor, zero per-byte bounds/flush checks. Old per-byte code kept as
   `writeUtf8Slow` for buffer-spanning writes.
3. `utf8Length`: ASCII prefix scan (1 compare/char) before the general loop.
4. `writeArrayUnsigned/Signed(byte[]/short[])`: hoisted-cursor inline varint
   loops, matching the existing `int[]`/`long[]` versions.

`IStream.java`
5. `feed`: steady-state case (`state == IDLE && varintShift == 0` → `fastField`)
   checked **first** in the loop.
6. `fastField` (header + scalar varint) and `fastVarintArray` (elements): when
   ≥10 bytes remain, decode the varint with **no per-byte bounds check**,
   continuation tested via the raw byte's sign bit (`b < 0`), identical
   overflow semantics (max 10 bytes, then `INVALID_MSG "varint overflow"`).
   The per-byte checked loops remain as the buffer-tail/spill path, so
   split-feed streaming behavior is unchanged.

### sofabgen Java backend (`generator/generators/java/`, +56/−7)

7. `encode()`: marshals into a **per-thread scratch buffer**
   (`ThreadLocal<byte[]>(MAX_SIZE)`) instead of allocating + zeroing a fresh
   worst-case array per call; the returned exact-size `Arrays.copyOf` is now the
   only allocation — same count as protobuf's `toByteArray()`.
   (Documented caveat: `encode()` must not be re-entered from a `marshal()`
   override on the same thread.)
8. Blob omit check with empty default: `x == null || x.length != 0` instead of
   `!Arrays.equals(x, new byte[0])` (killed a per-encode allocation).
9. String omit check: `x == null || !x.isEmpty()` (empty default) /
   `!"def".equals(x)` — same truth table as `Objects.equals`, no static-call hop.
10. Visitor: `ByteArrayOutputStream acc` now lazy — only allocated if a
    string/blob actually arrives split across feeds (never, in whole-message use).
11. Field initializers reference shared `Sbuf.EMPTY_LONGS/FLOATS/DOUBLES/BYTES`
    constants instead of allocating per-instance empty arrays.

Nothing about the wire format changed; every target still emits the canonical
434-byte wire with the reference sha.

## 4. Verification

- `corelib-java`: `mvn test` → **614/614 pass** (RoundTrip, StreamingEdge,
  DecoderErrors, StateMachineCoverage, 533 VectorConformance…).
- `generator`: `go test ./...` → all pass; `tests/matrix` goldens regenerated
  (Sbuf/Scalars only — no other language backend drifted).
- Arena self-check: warm-up round-trip re-encode byte-identity + sha gate pass;
  sofab sha unchanged before/after.
- A/B method: baseline jars rebuilt from clean git state (`git stash`),
  optimized jars from the working tree; 7 interleaved rounds of
  base → opt → protobuf at 2 M iters; medians reported (VPS is noisy — single
  runs swing ±8%; protobuf served as per-round control).

Post-optimization profile: string cost now concentrated in the (bulk) `writeUtf8`
itself; per-byte `pushByte`/`charAt` frames are gone from the encode profile;
decode `fastVarintArray` share fell from 25% → 20% while absolute time dropped ~15%.

## 5. Plan to land these optimizations (upstream implementation plan)

All work is local to this VPS (nothing pushed), staged as clean diffs in three repos:

| repo | change | risk |
|---|---|---|
| `corelib-java` | `OStream.java`, `IStream.java` (items 1–6) | low — covered by conformance vectors + streaming edge tests |
| `generator` | `generators/java/{backend,helpers,visitor}.go` + regenerated `tests/matrix` goldens (items 7–11) | low — golden-gated |
| `arena` | regenerated `languages/java/sofab/gen` sources; `results/RESULTS.txt` java row | derived artifacts |

Suggested landing order:
1. **PR 1 — corelib-java hot paths** (items 1–6). Pure runtime change, no API
   surface change; ship first since it benefits every existing generated project.
   Include a note that decoder fast/slow paths stay byte-for-byte equivalent.
2. **PR 2 — generator Java backend** (items 7–11) + regenerated goldens. Release
   as a sofabgen minor bump; call out the `encode()` re-entrancy caveat in the
   generated Javadoc (already emitted as a comment).
3. **Arena refresh** after both merge: `./scripts/run_benchmark.sh` full run to
   regenerate `RESULTS.txt` on the reference machine (this table's other rows are
   from the previous full run; only the java row was re-measured here — the
   other rows also still show the pre-v0.11.0 436 B sofab wire).

### Remaining headroom (future work, in expected-impact order)

- **Bulk array callbacks in `Visitor`** (decode): per-element virtual
  `unsigned/signed` calls + the generated double-switch cost ~10% of decode for
  the 40 int-array elements. An opt-in `arrayUnsigned(int id, long[] values)`
  default method (lib fills a scratch array) or a generated-side "current array
  target" pointer would cut most of it — but it touches the public Visitor API
  and the borrowed-view memory model, so it needs a family-wide design decision.
- **Decoder field-loop fusion**: keep the cursor in `fastField` across
  consecutive fields to drop per-field `feed`-loop dispatch (~6% of decode).
- **`readLe32/64` via `VarHandle`** little-endian views (JDK 9+) instead of
  byte-assembly, for the 10 floats (~4% of decode).
- **Encode size memoization** (protobuf-style) is *not* recommended: it requires
  immutability or dirty-tracking, which contradicts the mutable-POJO model; the
  ThreadLocal scratch already removes the allocation asymmetry.

### Reproduce

```bash
# full java A/B (jars + script preserved on this VPS scratchpad):
BENCH_ITERS=2000000 <scratchpad>/ab.sh 7
# official arena row:
cd /workspace/arena && LANGS=java RUNS=5 ./scripts/run_benchmark.sh --no-setup
# profiles: async-profiler 3.0, -agentpath:...=start,event=itimer,interval=1ms
```
