# C/C++ throughput regression: cpp, cpp/heapfree, cpp-embedded, c-embedded (2026-09-18)

Reproduced on this box (Ryzen 7 5700U, WSL2, `taskset -c 2`, best of 5–7 interleaved rounds,
`BENCH_ITERS=500000`, sha256 gate checked on every run). **OLD** = arena @1971be6 generated code +
corelib-cpp `31e4b15` / corelib-c-cpp `f881c24` (the tips on 2026-08-19). **NEW** = HEAD +
corelib-cpp `3bfa154` / corelib-c-cpp `7b68297`. The timed loops and harnesses did not change
between the two (`git diff 1971be6 HEAD -- languages/{cpp,cpp-embedded,c-embedded,common}` touches
only the generated headers).

| row | OLD MB/s | NEW MB/s | Δ | corelib fixes | + generator fix |
|---|--:|--:|--:|--:|--:|
| cpp / sofab | 268.1 | 249.4 | −7.0 % | 259.7 (+4.1 %) | **294.6 (+18 %)** |
| cpp / sofab-heapfree | 389.1 | 368.4 | −5.3 % | 379.0 (+2.9 %) | 379.5 (no change) |
| cpp-embedded / sofab | 141.8 | 127.6 | −10.0 % | 135.6 (+6.2 %) | — |
| c-embedded / sofab | 112.6 | 113.6 | **noise** | 113.9 | — |

protobuf C++ stays at 258–260 MB/s. With both fixes cpp/sofab is at 1.13× MB/s (was 1.03× on NEW).
**c-embedded has no regression**: callgrind gives the same instruction count for OLD and NEW
(797,716,676 vs 797,716,687 Ir), and interleaved runs are equal. The README's 122 → 117 comes from
run-to-run variation.

## Root causes (bisected end-to-end, then ablated)

**1. corelib-c-cpp `fe86011` (#152, "LimitExceeded … caps where §6.2.1 binds"): −6 % on cpp-embedded.**
Bisect (best-of-5 MB/s): `81959d2` 141.0 → `08f0cd5` 138.0 → **`fe86011` 128.9** → `b1bdb2a` 128.4 →
`d4e6e4f` 127.9 → HEAD 126.6. The gen-old/gen-new swap at the same corelib moves nothing. #152
(and then #159, `d4e6e4f`) routes every `readString/readBlob/readArray` through `refuse()`,
`refuseSchema()`, `refuseUnbounded()`, …. At `-Os`, GCC keeps these out of line. Callgrind shows
`refuse`/`refuseSchema` as separate functions, each called 48× per message. The constant schema
bound (`5`, `32`) and the static `InlineVector`/`FixedString` capacity are then never folded.
The C core (`istream.c`) did not change in any way that matters.
- Residual (~4 %): with the new wrapper, GCC no longer inlines `sofab_istream_feed` into
  `Example::decode` (−450 Ir/msg in the byte loop). Ablation: `noinline` on the OLD tree costs
  −3.5 %. Forcing it inline on NEW is *worse* (123.5). This is an `-Os` inliner/layout effect and
  has no code-level fix. `08f0cd5` (string length from the value, not `strlen`) is also a layout
  effect, not a cost: encode runs 7 % *faster* in a split timing, and decode moves by 3–5 % with no
  change to the decode code.

**2. corelib-cpp field-span cap (`0198cf0`/`8cb6f20`/`98de0bc`, §6.2.1 #26/#129): −4.5 % heapfree, −2 % dynamic.**
Every nested field runs `exceedsBuffer(spannedLive(), 0)` in `beginField`, and every top-level
field runs `exceedsBufferAtHeader()`. The generator states `Limits{SIZE_MAX}`, so every one of
those checks returns false. Ablation with both checks deleted: heapfree 367.8 → 384.4, sofab
249.7 → 254.8.

**3. corelib-cpp `a7cbfa7` (#127, "fix the eager fitDest"): duplicated work, growable destinations only.**
The free `sofab::readString/readBlob/readArray` repeat, in front of the member read, the §7.3 tag
test, the bound/cap compare and the array reach. For a fixlen array the reach includes a 64-bit
`readable / fixLen_` division. The member read then does all of it again. Only `cpp/sofab` pays
this, which explains why it lost 2 points more than heapfree.

Bisect for cpp/heapfree: 388 → `a7cbfa7` 361 → `98de0bc` 352 → `4ff375f` (force-inline) 367 → HEAD 367.
What is left after fixes 1–3 (−2.6 % heapfree, −3.2 % sofab) comes from the resumable-parser
rewrite (`71be841`, `c9d3876`). Force-inlining `beginField` did not help (−1.8 %), so this part
is not attributed further.

**Found while profiling (not a regression): the generated `decode()` deep-copies the whole message.**
It returns `*in` from a local `IStreamObject`. That copy-constructs every `std::vector` and
`std::string` (`ExampleArrays::ExampleArrays(const&)` shows up in the profile), so every decode
allocates twice.

## Fix plan

| where | change | measured gain |
|---|---|--:|
| **corelib-c-cpp PR** — `a527b31` | `[[gnu::always_inline]]` on the five `refuse*` comparators. Verdicts and their order are unchanged. | cpp-embedded **+6.2 %** (127.6 → 135.6), unchanged across 3 alignment settings. Footprint: cpp-embedded −745 B text, cpp-cortex-m ±0, cpp-riscv +8 B |
| **corelib-cpp PR** — `1489fdc` | Hoist the field-span cap: once per `parseWindow`, if `spanCarry_ + n + ARRAY_MAX·FIXLEN_MAX ≤ max_buffered_field`, no field in the window can cross the budget, so the per-field tests are skipped. This is not an unlimited mode: a budget that can be reached keeps the per-field checks exactly as before. | heapfree **+3.7 %**, sofab +2 % |
| **corelib-cpp PR** — `921b6b0` | The member reads take an optional sizer. The free reads pass `detail::FitDest`, which runs after the read's own tag/bound/cap checks. Each check runs once and the visitor still decides growth. | sofab **+2.5 %** (7 rounds), heapfree unchanged |
| **generator (sofabgen, C++ backend)** | In `static T decode(...)`, emit `return std::move(*in);` instead of `return *in;`. `in` is a local that is about to be destroyed. A prototype hand-edit of `gen/example.hpp` was measured. | sofab **+13 %** on top of the corelib fixes (259.7 → 294.6), heapfree ±0 |
| environment | none: c-embedded is noise, and the cpp-embedded residual is `-Os` inlining/layout | — |

Rejected prototype: passing the sizer by reference, without forcing inlining, costs heapfree −3.5 %.
The committed `921b6b0` passes an empty sizer by value, with `always_inline`.

Conformance: corelib-cpp ctest passes 6/6 after each commit (the shared 131-vector suite and skip
matrix, §6.2.1 `header_limits`, §6.3). corelib-c-cpp ctest passes 5/5 (131 vectors, 11 invalid-UTF-8
vectors, `test_limits_c`, 865 C++ assertions). There is no clang on this box, so the CI clang leg
was not run locally. The wire is unchanged: 434 B, `e1733416…29d9d` on every measured run.

Branches (local only, not pushed): `perf/arena-regression-2026-09` in `vendor/corelib-cpp`
(`1489fdc`, `921b6b0`) and in `vendor/corelib-c-cpp` (`a527b31`).
