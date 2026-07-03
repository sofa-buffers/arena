# SofaBuffers maxspeed — cross-language bottleneck analysis

Status: **living document**, started 2026-07-03. Baseline is the arena run in
`results/RESULTS.txt`. Python is out of scope here (see the README note — its
ceiling is the CPython object model, tracked separately).

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

**Fix is a design change** — covered in `docs/perf/decode-design.md`.

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

### Java — primitive arrays instead of boxed `List<Long>` ✅
- **Decode + encode (generated-code, `primitive-arrays.patch`):** `ExampleArrays`
  fields changed from `List<Long>`/`List<Float>`/`List<Double>` to primitive
  `long[]`/`float[]`/`double[]`; the visitor allocates each array to its `count`
  in `arrayBegin` and fills by index (no autoboxing); `marshal` passes the
  primitive array straight to `OStream` (no `Sbuf.toLongArray` temp + unbox);
  `Json.from/to` updated to match. Also folded in the string/blob single-shot
  path (skips the **synchronized** `ByteArrayOutputStream`) and an unboxed `int[]`
  sequence stack. Re-applied by `languages/java/setup.sh` after generation.
- Removes ~50 boxing allocations per decode + 10 temp-array conversions per encode.
- Result: arena **0.62× → 0.80×** (177 → 230 MB/s), wire + sha256 unchanged.
  (protobuf-java also scales with warmup, so the ratio lands at 0.80× at 2M iters.)

### Go — use the corelib's contiguous fast path both ways ✅ (worst → parity)
- **Decode (generated-code):** generated `unmarshal` rewritten to implement
  `sofab.Visitor` and decode via the already-existing zero-copy
  `sofab.AcceptBytes` cursor instead of the pull API over `bufio` (kills per-byte
  `ReadByte` + per-float `make()`). Captured as
  `languages/go/sofab/decode-visitor.patch`, re-applied by `languages/go/setup.sh`
  after generation (idempotent).
  - Split bench: decode **5135 → 2240 ns/op**, **5432 → 1280 B/op**, **41 → 28 allocs**.
- **Encode (corelib):** `vendor/corelib-go/encoder.go` `Encoder` now accumulates
  into an internal byte slice (append) and writes once on `Flush`, instead of
  per-byte `WriteByte` through `bufio.Writer`; `WriteString` appends the string
  directly (no `[]byte(s)` copy). Streaming + sticky-error contracts preserved via
  a 4 KB threshold flush — **all corelib-go tests pass**.
  - Split bench: encode **4062 → 1446 ns/op**, **4816 → 1008 B/op**, **13 → 3 allocs**.
- **Combined arena result: go sofab 0.46× → ~1.0× — parity with protobuf**
  (≈64 → ≈136 MB/s), wire + sha256 unchanged.

### C# — string/blob single-shot decode (Mistake 1) ✅
- Change: `languages/csharp/sofab/gen/Message.cs` `ExampleVisitor.String/Blob`,
  captured as `languages/csharp/sofab/single-shot-strings.patch` and re-applied by
  `languages/csharp/setup.sh` after generation (idempotent).
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
| 7 | Rust | drop per-decode `stack`/`acc` Vecs; `reserve(count)` arrays | generated-code | TODO |
| 8 | **all** | push/visitor → direct switch-into-fields decode | **design** | see `decode-design.md` |
| 9 | TS | stop emitting dead `new ChunkAcc()` in string/blob-free visitors | generated-code | TODO (quick) |

Every generated-code fix should be captured as a `*.patch` beside the target and
re-applied in that language's `setup.sh` (as C# and TS do), so the arena stays
reproducible until the fixes land in the generator itself.
