# SofaBuffers maxspeed — cross-language bottleneck analysis

Status: **living document**, started 2026-07-03, last revised 2026-07-17. Baseline
is the arena run in `results/RESULTS.txt`. Python is out of scope here (see the
README note — its ceiling is the CPython object model, tracked separately).

> This document is the **benchmark-side analysis** — what was slow, what was
> measured, and the resulting standings. The **codegen implementation guides**
> (how each fix is emitted per language, plus the decode-design rationale and
> reference patches) live in the generator repo:
> [`sofa-buffers/generator` → `docs/perf-patches/`](https://github.com/sofa-buffers/generator/tree/main/docs/perf-patches).
> Every fix in the *2026-07 round* below is emitted natively by **sofabgen v0.6.0**.
>
> **Java has a dedicated deep-dive:** [`java-analysis.md`](java-analysis.md)
> (2026-07-17) — split encode/decode timings, exact allocation accounting, and the
> measured fixes. It supersedes every Java claim in this file.
>
> **2026-09 regression round:** [`regressions/README.md`](regressions/README.md) — per-language OLD→NEW bisects, root causes and prototyped fixes.

## Read the metric before reading the standings

`speed adv = sofab_MBps / protobuf_MBps`. **`MB/s` divides by the wire size**, and
the gate guarantees the sofab wire is 434 B against protobuf's 494 B *in every
target*. So the ratio always decomposes into two independent factors:

```
speed adv = (434 / t_sofab) / (494 / t_proto)
          = 0.8785            ×  (t_proto / t_sofab)
            └ size handicap      └ real per-message speed
```

**The 0.8785 is constant across all 18 targets** — it is arithmetic, not a
measurement. Consequences worth internalizing before optimizing anything:

- **`adv = 1.00` does not mean parity.** It means SofaBuffers is already **13.8 %
  faster per message** — it just has 12 % fewer bytes to be credited for.
- The metric **charges SofaBuffers for its own headline feature** (the smaller wire).
- To read real work, divide out the constant: `t_proto/t_sofab = adv / 0.8785`.

| language | `adv` (README) | **real per-message speed** (`adv / 0.8785`) |
|---|--:|--:|
| Zig | 1.86× | **2.12×** |
| Rust | 1.49× | **1.70×** |
| C# | 1.44× | **1.64×** |
| C++ | 1.21× | **1.38×** |
| Go | 1.03× | **1.17×** |
| **Java** | **0.85×** | **0.97× — near parity, not a 15 % deficit** |
| TS · Node | 0.65× | 0.74× |
| Python | 0.10× | 0.11× |

This is **not** a bug in the arena: the metric is applied identically everywhere, so
rows stay internally comparable, and SofaBuffers wins most of them *despite* the
handicap. But it does mean **the Java row was over-read as a problem** — see
[`java-analysis.md`](java-analysis.md) §3.1 and backlog #12.

## The standings we set out to close (2026-07-03, historical)

The starting point of the fix round documented under *Measured proof*, kept for the
record — **not** current numbers (those live in the README):

| language   | speed adv | verdict |
|------------|----------:|---------|
| **C++**    | **1.45×** | the reference — SofaBuffers *beats* protobuf |
| rust       | 0.86×     | close |
| C#         | 0.81×     | close |
| java       | 0.62×     | mid |
| typescript | 0.55×     | mid |
| go         | 0.46×     | worst |

The same wire format ran at 1.45× in C++ and 0.46× in Go. **The format is not
the problem — the language runtimes above the byte codec are.**

## The one finding that explains almost everything

We profiled/read the encode+decode hot path in every language against the C++
reference. The result is remarkably consistent:

> The corelib **byte-level codec is fine** in every language (contiguous
> cursor/pointer-advance, tight varint loops). The gap to C++ lives in the
> **layer above it** — the generated per-message code and its data model — and
> it is the *same three mistakes* almost everywhere.

C++ is fast because its generated `deserialize(is, id)` does **one `switch(id)`
that reads straight into a struct field** over the contiguous buffer, its arrays
are **fixed-size `std::array<T,5>` on the stack**, its encode buffer is a **stack
buffer**, and LTO inlines/devirtualizes/vectorizes the lot. Every slower language
diverges from one or more of those on the hot path.

### Mistake 1 — the string/blob "accumulator" anti-pattern  *(generated-code)*
The generated visitor copies each string/blob payload **byte-by-byte into a
growable buffer**, then copies it out again — even though the corelib's contiguous
path already hands the visitor the **whole payload in one chunk**.

| lang | what it does today | file |
|------|--------------------|------|
| C#   | `for … acc.Add(data[i])` → `acc.ToArray()` → `GetString` | `Message.cs` `ExampleVisitor.String/Blob` |
| Java | **fixed (v0.6.0)** — single-shot `new String(data, off, total, UTF_8)`; the `synchronized` `ByteArrayOutputStream` is now only the lazy split-chunk fallback | `Example.java:195-229` |
| Rust | `acc.extend_from_slice` → `from_utf8_lossy().into_owned()` (double copy) | `message.rs` `string()/blob()` |
| TS   | **already fixed** — `ChunkAcc` single-shot path | `message.ts` |

**Fix:** when `offset==0 && chunkLength>=total` (the common single-chunk case),
build the string/blob directly from the slice; keep the accumulator only as the
split-chunk fallback. This is exactly the TS `ChunkAcc` optimization, generalized.
**✅ Implemented + measured for C# — see below.**

### Mistake 2 — heap/boxed array model instead of fixed primitive arrays  *(design / generated-code)*
Schema arrays are **fixed size 5**. C++ stores them as `std::array<T,5>` (stack,
zero heap). The others store growable, often boxed, heap collections and fill them
one element at a time:

| lang | model | cost per decode |
|------|-------|-----------------|
| Java | **fixed (v0.6.0)** — primitive `long[]`/`float[]`/`double[]` at schema count | boxing gone; see the *new* Java issues below |
| C#   | `List<T>` + per-elem `Add`, `.ToArray()` per array on encode | ~10 array allocations on encode |
| Rust | `Vec<T>` per array | ~15–20 `malloc`/`free` per decode |
| TS   | `number[]` / `bigint[]` filled per element | GC pressure; megamorphic per-elem writes |

**Fix:** generate fixed-size primitive arrays (`long[]`/`float[]` in Java,
`[T;5]` in Rust, `Uint32Array`/`Float64Array` in TS, pre-sized in C#) and a corelib
**bulk** array read/write so the tight loop fills a primitive buffer with no boxing
and no per-element dispatch.

> **Caveat learned in Java (2026-07-17):** *narrower* is not automatically *faster*.
> Java's corelib already ships `byte[]`/`short[]`/`int[]`/`long[]` overloads for every
> integer array writer, and switching `u8→byte[]`, `u16→short[]`, `u32→int[]` (so the
> varint loop is 5-byte instead of 10-byte capable) measured **throughput-neutral to
> slightly negative** — it only cut 144 B/op of memory. Narrow arrays are a *footprint*
> argument, not a speed one. Don't port this to C#/Rust expecting throughput.

### Mistake 3 — per-decode scratch allocation + the push/visitor double-dispatch  *(design)*
Every decode allocates a fresh visitor + stream + a `stack` (Stack/ArrayDeque/Vec)
+ an `acc`, and dispatches each field through a **visitor interface method that
then does a second `switch` to store the value**. C++ does a single switch into
fields with no per-field call and no scratch objects.

- In **TypeScript** this is the top cost: `FastDecoder.run` calls `top.unsigned?.(…)`
  where `top` cycles through 5+ visitor object shapes per decode → the call sites
  are **megamorphic**, so V8 can't inline them (`vendor/corelib-ts/.../decode/fast.ts`).
- In **C#/Java** the call is monomorphic (only one visitor type) so it's cheaper,
  but the double-`switch` + scratch allocation remains.
- In **Go** it's worse still — see below.

**Fix is a design change** — the rationale and how it ports to every language lives
with the codegen guides in the generator repo:
[`docs/perf-patches/decode-design.md`](https://github.com/sofa-buffers/generator/blob/main/docs/perf-patches/decode-design.md).

> **Java measurement (2026-07-17) argues against porting this to the JVM.** With the
> monomorphic visitor *and* the per-element interface dispatch still in place, Java's
> sofab decode already **beats protobuf-java** (1138 vs 1176 ns/op) while allocating
> **18 % less**. C2 devirtualizes and inlines the monomorphic call, so the
> double-`switch` costs little. The design change is a real win where dispatch is
> megamorphic (TS) — it is **not** where the JVM's remaining headroom is. Java's
> deficit is entirely on the **encode** side.

## Go is a special case — it doesn't even use its own fast path

Go's corelib **already has** a zero-copy contiguous decoder — `cursor.go` +
`Decoder.Accept(v)` / **`AcceptBytes(buf, v)`** (documented "the fastest entry
point when the message is already in memory (e.g. generated Unmarshal code)").
The generated `unmarshal` **ignores it** and uses the slow pull API instead:

- `sofab.NewDecoder(bytes.NewReader(data))` → every varint byte pulled through
  `bufio.Reader.ReadByte()` — a **per-byte interface call** (`decoder.go:86`).
- `readRaw` does `make([]byte, n)` **per float element** in array decode
  (`decoder.go:125`, called in the fp-array loops).
- Encode goes through `bytes.Buffer` wrapped in `bufio.Writer` with per-byte
  `WriteByte` (`encoder.go:55`) and `[]byte(s)` copies per string.

**Fix:** (a) *generated-code* — decode via `AcceptBytes` + a generated `Visitor`
(uses the existing fast path, no corelib change); (b) *corelib* — give the
`Encoder` a byte-slice backing instead of `bufio.Writer` over `bytes.Buffer`.
Go has the most headroom (0.46×) and the clearest fixes.

## Encode-side issues *(generated-code / corelib)*
- **C#/Java:** `new byte[MaxSize]` scratch + a second right-sized `Array.Copy`/
  `Arrays.copyOf` per encode. Fix: `ArrayPool`/`stackalloc` scratch (C#), reuse
  scratch + return length (Java); avoid the boxed→primitive conversions (Mistake 2).
  Java's scratch is now a `ThreadLocal<byte[]>` (v0.12.0), so only the exact-size
  copy-out remains; an `encodeInto(byte[])` that skips it measured **650 ns/op at
  0 B/op** vs `encode()`'s 855 (backlog #11).
- **Rust/TS:** encode is **already good** — pooled/reused buffer, no per-iter alloc.

### Mistake 4 — the allocating default-check *(generated-code)* — **NEW, Java-confirmed**
The array default-guard allocates a throwaway zero array **per field, per encode**:

```java
if (!java.util.Arrays.equals(this.u8, new long[5])) { … }   // ← new long[5] every encode
```

`Arrays.equals` is a vectorized intrinsic, which defeats escape analysis — the array
is really allocated. In Java that is **544 B/op of pure garbage** (8× `long[5]` +
`float[5]` + `double[5]`), and the allocation accounting closes to within 1 B of the
measured 1001 B/op. Replacing it with an allocation-free scan cut **encode by 11.3 %**
(855 → 758 ns/op), wire and SHA-256 unchanged.

**This is a Java-backend defect, not a design-wide one — verified, not assumed.** The
other fixed-array backends already emit the correct shape:

| backend | default guard | allocates? |
|---|---|---|
| **Java** | `!Arrays.equals(this.u8, new long[5])` | **yes — 544 B/op** |
| C# | `!SequenceEqual(this.u8, _arrdef_u8)`, with `private static readonly byte[] _arrdef_u8 = new byte[5]` | no — hoisted to a static |
| Rust | `self.u8 != [0; 5]` | no — stack literal, LLVM constant-folds it |

So the generator **already knows the right pattern** (C#'s hoisted `_arrdef_*` static)
and simply fails to apply it in the Java template. The minimal fix is the C# shape —
a `private static final long[] ARRDEF_U8` — though the measured −11.3 % used an
allocation-free scan (`anyNonZero`) that skips the comparison entirely; the
hoisted-constant variant was **not** separately measured.

Related, and also a Java-only gap: each array is walked **three times** per encode —
`Arrays.equals` (scan 1), `Sbuf.trimTail` (scan 2), then the write. Rust's `_trim_tail`
returns a **slice** (`&[T]`, zero-copy); Java's returns `Arrays.copyOf` and therefore
*allocates* whenever an array actually has trailing defaults (invisible in this
benchmark, whose arrays all end non-zero). Java has no slice type — the fix is
`writeArray*(id, a, from, len)` overloads in the corelib (backlog #10).

This was **introduced by the v0.6.0 fixed-primitive-array fold itself** — the same
change that removed the boxing. A reminder that the *measured proof* below is proof
of the delta, not of the absence of new regressions.

## Build flags — checked, not a bottleneck
Rust (`-C target-cpu=native` + `lto=true` + `codegen-units=1`), Java (C2 + 20k-iter
warmup), C# (Release + TieredPGO + tuned GC), TS (tsx→esbuild→V8 JIT + 10k warmup)
are all built/warmed correctly and identically to their protobuf baselines. No
free wins here.

---

## Measured proof so far

### TypeScript — monomorphic pull decoder (design change) ✅ decode; ⚠ encode-bound
- **Decode (corelib + generated-code):** implemented design C (see the generator
  repo's [`decode-design.md`](https://github.com/sofa-buffers/generator/blob/main/docs/perf-patches/decode-design.md)).
  New corelib `Cursor` pull decoder
  (`vendor/corelib-ts/src/decode/cursor.ts`, **corelib-ts PR #16**) exposes typed
  `read*` over a numeric cursor on the `Uint8Array` (visitor/`FastDecoder` API kept
  for streaming). Generated `message.ts` now emits a **monomorphic `static
  decode` / `decodeFrom(Cursor)`** per type — one `switch(id)` reading straight into
  fields, no per-decode visitor closures or `ChunkAcc` (was megamorphic dispatch
  across 5+ visitor shapes). **Now emitted by sofabgen** (folded into codegen
  upstream, generator v0.6.0), so no arena patch is needed — a fresh generate
  carries it.
  **Decode-only: 80.5 → 98.6 MB/s (+22%)**; corelib 379 tests pass; sha256 unchanged.
- **Encode (corelib + generated-code):** the round-trip was encode-bound — encode
  was ~64% of the loop and ~8200 ns/op. ~60% of that was `writeString` deferring to
  `TextEncoder.encode()` (per-call WHATWG setup + a throwaway `Uint8Array` per
  string + a second copy). Fixed in corelib-ts (**PR #17**): an allocation-free
  two-pass `utf8Length`/`utf8Write` that reproduces `TextEncoder` byte-for-byte
  (incl. lone-surrogate → U+FFFD); streaming path unchanged. Plus generated-code
  tweaks (blob default-guard `!arrEq(...)` → `.length !== 0`, string-list
  `forEach` → indexed `for`) — **now emitted by sofabgen** (generator v0.6.0), no
  arena patch needed.
  **Encode-only: 7250 → ~4000 ns/op (−45%)** — now *below* protobufjs encode (~5014).
- **Combined result: TS 0.54× → ~0.81×** (≈35 → ≈51 MB/s), sha256 unchanged.

### Rust — fixed-size arrays instead of `Vec<T>` ✅ (now *beats* protobuf)
- **Decode (generated-code, `fixed-arrays.patch`):** `ExampleArrays` fields changed
  from `Vec<u8>`/`Vec<f32>`/… to stack `[T; 5]` (like C++'s `std::array<T,5>`);
  the visitor fills them by index (no per-array heap allocation), `array_begin`
  just resets the index, and the struct default/marshal use the fixed arrays.
  Also folded in the string/blob single-shot path (skips the `acc` accumulate +
  `into_owned()` double copy). serde handles the JSON round-trip unchanged.
  **Now emitted by sofabgen** (folded into codegen upstream, generator v0.6.0), so
  no arena patch is needed — a fresh generate carries it.
- Removes ~15–20 heap allocations per decode (the agent-identified dominant cost).
- Result: arena **0.85× → 1.40×** (217 → 358 MB/s) — Rust now beats protobuf,
  like C++. Wire + sha256 unchanged.

### Java — primitive arrays instead of boxed `List<Long>` ✅
- **Decode + encode (generated-code, `primitive-arrays.patch`):** `ExampleArrays`
  fields changed from `List<Long>`/`List<Float>`/`List<Double>` to primitive
  `long[]`/`float[]`/`double[]`; the visitor allocates each array to its `count`
  in `arrayBegin` and fills by index (no autoboxing); `marshal` passes the
  primitive array straight to `OStream` (no `Sbuf.toLongArray` temp + unbox);
  `Json.from/to` updated to match. Also folded in the string/blob single-shot
  path (skips the **synchronized** `ByteArrayOutputStream`) and an unboxed `int[]`
  sequence stack. **Now emitted by sofabgen** (folded into codegen upstream,
  generator v0.6.0), so no arena patch is needed — a fresh generate carries it.
- Removes ~50 boxing allocations per decode + 10 temp-array conversions per encode.
- Result: arena **0.62× → 0.80×** (177 → 230 MB/s), wire + sha256 unchanged.
  (protobuf-java also scales with warmup, so the ratio lands at 0.80× at 2M iters.)

### Java — the 2026-07-17 re-analysis ⚠️ *the row was over-read*
Full write-up: [`java-analysis.md`](java-analysis.md). Split encode/decode, medians of
9 interleaved rounds (noisy WSL2 host — treat <3 % as unresolvable; **re-measure on the
reference HW**):

| | encode | decode | round trip |
|---|--:|--:|--:|
| sofab (as shipped) | 855 ns / 1001 B | **1138 ns** / 1952 B | 1824 ns / 2944 B |
| protobuf | **714 ns** / 768 B | 1176 ns / 2384 B | **1780 ns** / 3152 B |

1. **Java is at ~0.97× per message, not 0.85×** — the rest is the size handicap (see
   *Read the metric* above). In msgs/s: 548k vs 562k.
2. **Decode already wins** (0.979×) at 18 % less garbage. The remaining deficit is
   **100 % encode**.
3. **Mistake 4** (above) is the one real, fixable regress: encode −11.3 %, wire identical.
4. **protobuf's encode number is itself an artifact.** `getSerializedSize()` is
   memoized on the immutable message (`Message.java:4931`, `memoizedSize`), and the
   arena re-serializes **one** `src` 2M times — so the size pass is paid **once, not
   2M times**. Encoding a *freshly decoded* message costs **~888 vs 662 ns/op (+34 %)**.
   Memoization is a legitimate protobuf feature — but the arena currently measures
   protobuf's **re-serialization** against SofaBuffers' **serialization**, and does not
   say so (backlog #13).
   - **Varying the payload does not fix this** — measured: cycling 64 pre-built distinct
     messages leaves encode unchanged (648 vs 662 ns). The artifact is bound to
     *instance reuse*, not payload constancy; each pre-built message memoizes on its own
     first encode. Invalidating it requires building in-loop, which drags construction
     into the measurement (contract violation, and unfair to protobuf).
   - **Chaining the round trip does** — `decode(blob).encode()` instead of
     `encode(src); decode(b)`. `parseFrom`→`buildPartial()` yields a fresh instance
     (`memoizedSize = -1`), so the size pass is paid with no construction added and
     memoization left enabled. Java, medians: sofab 1851→1829 ns (noise), protobuf
     1803→**2033** ns; `adv` 0.856→**0.977**, per-message 0.974→**1.112**.
     **Likely affects every maxspeed row** (protobuf memoizes size in C++/C#/Go too) —
     unverified outside Java. See [`java-analysis.md`](java-analysis.md) §3.4.
5. **Negative results worth not repeating:** narrow arrays → neutral (see Mistake 2
   caveat); reusing/zeroing the decode arrays instead of reallocating → **time-neutral**,
   −544 B/op (a GC-pressure win only); `OStream.BULK_MIN` 16 → 2 → within noise.

### Go — use the corelib's contiguous fast path both ways ✅ (worst → parity)
- **Decode (generated-code):** generated `unmarshal` rewritten to implement
  `sofab.Visitor` and decode via the already-existing zero-copy
  `sofab.AcceptBytes` cursor instead of the pull API over `bufio` (kills per-byte
  `ReadByte` + per-float `make()`). **Now emitted by sofabgen** (folded into
  codegen upstream, generator v0.6.0), so no arena patch is needed — a fresh
  generate carries it.
  - Split bench: decode **5135 → 2240 ns/op**, **5432 → 1280 B/op**, **41 → 28 allocs**.
- **Encode (corelib):** `corelib-go`'s `Encoder` now accumulates into an internal
  byte slice (append) and writes once on `Flush`, instead of per-byte `WriteByte`
  through `bufio.Writer`; `WriteString` appends the string directly (no `[]byte(s)`
  copy). Streaming + sticky-error contracts preserved via a 4 KB threshold flush —
  all corelib-go tests pass. **Merged upstream** (corelib-go PR #28), so no arena
  patch is needed — a fresh clone carries it.
  - Split bench: encode **4062 → 1446 ns/op**, **4816 → 1008 B/op**, **13 → 3 allocs**.
- **Combined arena result: go sofab 0.46× → ~1.0× — parity with protobuf**
  (≈64 → ≈136 MB/s), wire + sha256 unchanged.

### C# — string/blob single-shot decode (Mistake 1) ✅
- Change: `ExampleVisitor.String/Blob` decode straight from the contiguous chunk.
  **Now emitted by sofabgen** (folded into codegen upstream, generator v0.6.0), so
  no arena patch is needed — a fresh generate carries it.
- Result: arena **0.81× → 0.88×** (114.8 → 122.6 MB/s), wire + sha256 unchanged.
- This is the smallest, safest of the fixes; the array-model and encode-buffer
  fixes below stack on top of it.

---

## Prioritized backlog (highest impact first)

| # | language | fix | class | status |
|---|----------|-----|-------|--------|
| 1 | **Go** | decode via `AcceptBytes`+Visitor (use existing fast path) | generated-code | ✅ done |
| 2 | **Go** | `Encoder` → byte-slice buffer (drop `bufio`/`bytes.Buffer`) | corelib | ✅ done (Go now ~1.0×) |
| 3 | **Java** | primitive `long[]/float[]/double[]` arrays (kills boxing) + string single-shot | generated-code | ✅ done (0.62→0.88×) |
| 4 | **C#** | string/blob single-shot | generated-code | ✅ done (0.81→0.88×) |
| 5 | ~~C#/Java~~/Rust | string/blob single-shot | generated-code | ✅ C#+Java done (v0.6.0); **Rust** TODO |
| 6 | C# | encode: `ArrayPool`/`Span` scratch, no double-copy; `List<T>` overloads to kill `.ToArray()` | generated+corelib | TODO |
| 7 | Rust | fixed `[T;5]` arrays (kills per-array heap alloc) + string single-shot | generated-code | ✅ done (0.85→1.40×) |
| 8 | **all** | push/visitor → direct switch-into-fields decode | **design** | ✅ TS done (corelib-ts #16); **not worth it on the JVM** (Java decode already wins) |
| 9 | **TS** | **encode** tuning — allocation-free UTF-8 `writeString` (corelib-ts #17) + generated-code guards | generated+corelib | ✅ done (0.58→0.81×) |
| **10** | **Java** *(then C#/Rust)* | **Mistake 4** — allocation-free array default-check instead of `Arrays.equals(x, new T[n])`; fuse the check with `trimTail` into one pass | generated-code | **measured** (encode −11.3 %, −544 B/op, wire identical) — highest value/effort in the Java target |
| 11 | Java/C# | emit `encodeInto(byte[])`/`encodeTo(OStream)` + reuse the `OStream` — drops the exact-size copy-out | generated+corelib | measured (650 ns/op, **0 B/op**); API addition |
| **12** | **arena** | report **`msgs/s` (or `ns/op`) next to `MB/s`** — the ratio silently embeds a constant 0.8785 size handicap that made Java read as a 15 % deficit when it is ~3 % | methodology | **proposed** |
| 13 | **arena** | encode against a **freshly built** message, or report both — protobuf's memoized size currently hoists ~57 % of its encode work out of the timed loop | methodology | **proposed** — needs a fairness decision, not a code fix |

Items 1–9 landed in the generator (sofabgen v0.6.0), so the per-language `setup.sh` no
longer re-applies any `*.patch` — a fresh generate emits the optimized form directly.
The `*.patch` files and their re-apply blocks have been removed; `scripts/bootstrap.sh`
pins the generator release that carries the fold.

Items 10–11 are **measured but not upstreamed** — they belong in
`sofa-buffers/generator` / `corelib-java`, not in the arena (per `CLAUDE.md`). Items
12–13 are questions about what the arena *measures*; #13 in particular is a fairness
call to make deliberately (both framings are defensible), not a number to quietly
change in SofaBuffers' favour.
