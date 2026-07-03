# SofaBuffers maxspeed — cross-language bottleneck analysis

Status: **living document**, started 2026-07-03. Baseline is the arena run in
`results/RESULTS.txt`. Python is out of scope here (see the README note — its
ceiling is the CPython object model, tracked separately).

> This document is the **benchmark-side analysis** — what was slow, what was
> measured, and the resulting standings. The **codegen implementation guides**
> (how each fix is emitted per language, plus the decode-design rationale and
> reference patches) live in the generator repo:
> [`sofa-buffers/generator` → `docs/perf-patches/`](https://github.com/sofa-buffers/generator/tree/main/docs/perf-patches).
> Every fix below is now emitted natively by **sofabgen v0.6.0**.

## The standings we're closing

`speed adv = sofab_MBps / protobuf_MBps` (within-language; >1 = SofaBuffers wins):

| language   | speed adv | verdict |
|------------|----------:|---------|
| **C++**    | **1.45×** | the reference — SofaBuffers *beats* protobuf |
| rust       | 0.86×     | close |
| C#         | 0.81×     | close |
| java       | 0.62×     | mid |
| typescript | 0.55×     | mid |
| go         | 0.46×     | worst |

The same wire format runs at 1.45× in C++ and 0.46× in Go. **The format is not
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
| Java | `ByteArrayOutputStream.write` (**`synchronized`!**) → `toByteArray` → `new String` | `Example.java` visitor |
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
| Java | `List<Long>` / `List<Float>` | **~50 boxing allocations** + ArrayList growth; **+10 temp `long[]` + 50 unboxes on encode** |
| C#   | `List<T>` + per-elem `Add`, `.ToArray()` per array on encode | ~10 array allocations on encode |
| Rust | `Vec<T>` per array | ~15–20 `malloc`/`free` per decode |
| TS   | `number[]` / `bigint[]` filled per element | GC pressure; megamorphic per-elem writes |

**Fix:** generate fixed-size primitive arrays (`long[]`/`float[]` in Java,
`[T;5]` in Rust, `Uint32Array`/`Float64Array` in TS, pre-sized in C#) and a corelib
**bulk** array read/write so the tight loop fills a primitive buffer with no boxing
and no per-element dispatch. Java gains the most (boxing dominates its profile).

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
- **Rust/TS:** encode is **already good** — pooled/reused buffer, no per-iter alloc.

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
| 5 | C#/Java/Rust | string/blob single-shot (Java has `synchronized` BAOS!) | generated-code | Rust/Java TODO |
| 6 | C# | encode: `ArrayPool`/`Span` scratch, no double-copy; `List<T>` overloads to kill `.ToArray()` | generated+corelib | TODO |
| 7 | Rust | fixed `[T;5]` arrays (kills per-array heap alloc) + string single-shot | generated-code | ✅ done (0.85→1.40×) |
| 8 | **all** | push/visitor → direct switch-into-fields decode | **design** | ✅ TS done (corelib-ts #16); other langs already switch-based |
| 9 | **TS** | **encode** tuning — allocation-free UTF-8 `writeString` (corelib-ts #17) + generated-code guards | generated+corelib | ✅ done (0.58→0.81×) |

All of these generated-code fixes have now landed in the generator (sofabgen
v0.6.0), so the per-language `setup.sh` no longer re-applies any `*.patch` — a
fresh generate emits the optimized form directly. The `*.patch` files and their
re-apply blocks have been removed; `scripts/bootstrap.sh` pins the generator
release that carries the fold.
