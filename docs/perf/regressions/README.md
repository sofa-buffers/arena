# Throughput regressions 2026-09: index

OLD = arena `1971be6` generated code + the corelib tips of mid-August 2026. NEW = HEAD
(sofabgen `d865b92`) + the corelib tips of 2026-09-18. Every number was reproduced on the
same box with interleaved A/B runs, and every variant kept the 434 B reference wire. Details,
bisects and ablations are in the per-language files. Corelib fix branches are named
`perf/arena-regression-2026-09`; they exist locally in `vendor/` and were not pushed.

| language | old → new (sofab MB/s) | root cause | fix location | measured gain of prototyped fix |
|---|--:|---|---|---|
| [go](go.md) | 157.7 → 121.0 (−23 %) | Encoder allocates a 1 KB MaxDepth=255 pending stack every time (`db4933b`); push machine makes two calls per varint (`bdd5f8b`); StringSeq grows by doubling | corelib (4 commits) + generator (`WithMaxDepth`) | 154.5 (+28 %; corelib only 141.0) |
| [typescript](typescript.md) (Node) | 74.2 → 54.0 (−27 %) | typed-array destinations: ~20 throwaway empty typed arrays per decode, fp32 `.buffer` views, megamorphic `resolveTarget`; push-visitor redesign | generator (sentinels, `f32`) + corelib (3 commits) | 69.4 (+28.5 %) |
| [typescript-bun](typescript.md) | 77.6 → 51.8 (−33 %, pinned) | same as Node, and the visitor redesign costs more on JSC; plus unpinned Bun 1.4 parallel GC marking (protobufjs 53 → 33) | generator + corelib + env (pin Bun / `BUN_JSC_numberOfGCMarkers=1`) | 62.4 (+20.5 %, pinned) |
| [python](python.md) | 22.2 → 17.1 (−23 %) | pull API removed (`f70ad02`); the flat Visitor makes ~113 C→Python hook calls per decode | generator (Binding table route) + corelib (cdef readers, 2 Binding features) | 42.0 (+146 %, 1.9× OLD); corelib only +3–4 % |
| [dart](dart.md) | 113.9 → 101.9 (−10.6 %) | `a85402e` (#87): `onArrayDone` view makes the array argument polymorphic in AOT; encoder zeroes a 1 KiB pending stack | corelib (3 commits) + generator (`depth:`, indexed copy) | 111.3 (+9 %); 126.3 with indexed copy |
| [cpp](cpp.md) / sofab | 268.1 → 249.4 (−7 %) | field-span cap checked on every field; free reads repeat the member read's checks (`a7cbfa7`); generated `return *in` deep-copies the message | corelib-cpp (2 commits) + generator (`std::move`) | 294.6 (+18 %) |
| [cpp](cpp.md) / sofab-heapfree | 389.1 → 368.4 (−5.3 %) | field-span cap checked on every field (`0198cf0`/`98de0bc`) | corelib-cpp | 379.5 (+3 %) |
| [cpp-embedded](cpp.md) | 141.8 → 127.6 (−10 %) | `refuse*` helpers (`fe86011`, #152) stay out of line at `-Os`, so bounds are never folded | corelib-c-cpp (`always_inline`) | 135.6 (+6.2 %); ~4 % left is `-Os` layout |
| [c-embedded](cpp.md) | 112.6 → 113.6 | no regression (identical Ir); the README delta is run-to-run noise | — | — |
| [java](java.md) | 291.0 → 295.3 | no regression; the README −8 % on both columns compares different runs | env: re-baseline README | optional UTF-8 / inline split: +1 % (noise) |
| [csharp](csharp.md) | 207.5 → 192.7 (−7 %) | `8b678c6` (#100): 1020 B `InlineArray(255)` pending run zero-filled on each `new OStream` | corelib (`OStream.Reset`) + generator (thread-static encoder, lazy PayloadAcc, presized List) | 212.6 (+10.3 %, above OLD) |
| [rust](rust.md) / sofab | 300.6 → 382.8 (+27 %) | improvement: generator now emits `reserve_exact(count)` | generator (presize `string_array`, fixed decode stack) | 418.2 (+9.2 %) |
| [rust](rust.md) / sofab-heapless | 476.7 → 482.3 | no regression; stale README table | generator (fixed decode stack, 0 allocs) | 485.3 (+0.6 %) |
| [rust-embedded](rust.md) | 181.3 → 176.8 (−2.5 %) | code placement at opt-level=z; `PayloadAcc::new()` zero-fill adds 861 Ir | none (lazy accumulator rejected: slower, +240 B .text) | — |
| [zig](zig.md) | 474.3 → 464.6 (−2.1 %) | generator: `decode()` now copies (owns) every string/blob instead of borrowing | generator (validate-before-copy; borrowing entry point is Andreas's decision) | 467.4 (+0.6 %); borrowing 481.8 (+3.7 %) |

## Cross-cutting causes

- **Encoder state sized to MAX_DEPTH=255 at construction** (the CORELIB_PLAN "no allocation after
  construction" rule, §6.6): go `db4933b`, csharp `8b678c6`, dart `a85402e`. The generated one-shot
  encode builds a new encoder per message, so it allocates and zeroes about 1 KB each time. The shared
  fix keeps §6.6: the generator emits the schema's static nesting depth and passes it to the encoder
  (go `WithMaxDepth`, dart `depth:`), or reuses the encoder (C# `OStream.Reset`).
- **Pull cursor replaced by a push visitor/state machine**: go `bdd5f8b`, typescript `6112092`, python
  `f70ad02`. The push machine costs more per value: go's varint calls are no longer inlined, JSC
  dispatches worse, and Python makes C→Python calls. Part of this cost remains after the fixes (Node
  about −6 %, Bun about −20 %).
- **Growable arrays not pre-sized from the checked count**: rust gained +27 % from `reserve_exact`.
  Go (`reserveRows`), C# (`new(5)`), Dart (indexed copy) and rust `string_array` gain from the same
  fix. Apply it in every backend that fills a growable container element by element.
- **§6.2.1 limit checks placed on the hot path**: cpp-embedded runs `refuse*` out of line, cpp runs the
  field-span cap per field, and the cpp free reads check twice. The fixes hoist or inline these checks;
  none of them removes a check.
- **Not regressions**: java, rust/heapless and c-embedded. The README tables do not match
  `results/RESULTS.txt`. Refresh them with a full `RUNS=5` run before claiming a delta under about 4 %.
