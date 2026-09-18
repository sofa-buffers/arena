# Dart throughput regression (2026-09): analysis and fix plan

Target `languages/dart`, corelib-dart `6b22ae3`, sofabgen `0.0.0-20260918072500-d865b9213550`,
Dart SDK 3.12.2. Measured 2026-09-18 on the 16-core WSL2 box: AOT executables built exactly
as `setup.sh` does (`dart compile exe`), `taskset -c 2`, 1M iterations, interleaved A/B,
best of 5. Every variant emitted the 434 B reference wire (`e1733416…9d9d`) and passed its
self-check. Protobuf was not touched (59.2 MB/s, 120 k msg/s).

## Reproduced

| variant | sofab MB/s | msg/s | vs protobuf (MB/s) |
|---|--:|--:|--:|
| OLD: arena `1971be6` + corelib `8617f7a` (current at the README run, `f436ff1`) | 113.9 | 262 k | 1.92× |
| NEW: HEAD + corelib `6b22ae3` | 101.9 | 235 k | 1.72× |

That is **−10.6 %**. The timed loop (`sofab/bench.dart`, `common/bench_common.dart`) and
`setup.sh`/`bench.sh` are the same in both. Only the untimed `harness.dart` changed.

## Bisect: it is all one corelib commit

I built the OLD generated `message.dart` against each corelib commit that touched `lib/`
(package name rewritten after `e7f86e5`). All builds kept the wire.

| corelib | 63f397a | 311bba7 | fbdf1af | e7f86e5 | **a85402e** | debbbfc | cc038d3 |
|---|--:|--:|--:|--:|--:|--:|--:|
| MB/s | 113.7 | 114.2 | 114.7 | 115.2 | **100.5** | 99.0 | 100.5 |

- The generated code is neutral: the OLD generated code on HEAD corelib runs at 100.5 and the NEW generated code at 101.7.
- The visitor base, strict UTF-8, collector and rename commits are all flat.
- The whole loss comes from **`a85402e` "conformance: corelib-dart against CORELIB_PLAN@c837108" (#87)**.

## Root causes (callgrind on the AOT snapshot, confirmed by end-to-end ablation)

`dart compile aot-snapshot` keeps a `.symtab`, so `valgrind --tool=callgrind dartaotruntime
bench.aot` gives named Dart frames. Across `a85402e` the instruction count per round trip goes
from 40.6 k to 44.2 k Ir (+8.8 %).

1. **The array conveniences lost monomorphism.** The new default `onArrayDone` hands
   `onUnsignedArray`/`onSignedArray` either the destination or an
   `Int64List.sublistView(...)`. Because of that view branch, AOT type-flow now sees
   `_Int64List | _Int64ArrayView` as the argument. So `values[i]`, `length` and iteration in
   the generated handlers stop being inlined:
   - `Int64List.[]`: +570 Ir
   - `onUnsigned/SignedArray`: +864 Ir
   - `onArrayDone` itself: +559 Ir

   Before `a85402e` the corelib passed a fresh `Int64List(n)` directly, which is always concrete.
2. **Encoder `_pendingSeq = Int32List(maxDepth)`.** `a85402e` sizes the run at
   construction (§6.6), which makes it 255 slots, 1 KiB zeroed on every `encode()`. It used to be
   `Int32List(8)`, allocated lazily. Cost: `AllocateInt32ArrayStub` +246 Ir, plus GC pressure.
3. **Destination protocol overhead** (§6.6.3/§6.7.1): `_arrayDest`, `onArrayDest`/`super`,
   `onBytesDest`/`onBytesDone`, plus one `Uint8List` and a copy per string. These are mandated
   and spread thinly. Removing the string copy entirely gained only +0.9 %, which is noise, so I
   did not pursue it.
4. Minor (from `fbdf1af`, the generated code's switch to the corelib `StringSeq`): the collector
   allocates a `() => ''` closure through the generic `_reserve` for every element.

Checked and ruled out:
- **UTF-8 validated twice.** `decodeUtf8Strict` scans once.
- **`try/catch` in `_ContiguousDecoder.run`.** Removing it gained +0.4 %, which is noise.
- **Cheaper `_arrayDest` type/length checks.** 0.0 % in AOT, although the JIT profile blamed
  them. Kept only as cleanup.

## Fixes (corelib-dart branch `perf/arena-regression-2026-09`, local, not pushed)

Each step was measured end-to-end against the step before it.

| # | commit | change | kind | MB/s |
|---|---|---|---|--:|
| 1 | `8c5fdc2` | `_arrayDest` checks on the promoted concrete type, refusals `never-inline` | corelib | 101.7 → 101.7 (noise) |
| 2 | `5c56014` | default `onArrayDone`: a longer destination is delivered as `v.sublist(0,count)` (a copy), never a view, so the argument stays `_Int64List` | corelib | 101.7 → 107.6 (**+5.8 %**) |
| 3 | `b472d9a` | `Encoder(..., depth:)` / `Encoder.overBuffer(..., depth:)`: the run is sized from the caller's declared depth at construction. `1..255`, otherwise `invalidArgument`. Nesting past it is `invalidArgument`, and past 255 it is still `invalidMessage` | corelib + **generator** | 108.5 → 109.9 (**+1.3 %**); alone on NEW +2.8 % |
| 4 | `45cae29` | `StringSeq`/`BlobSeq` fill gaps inline, with no per-element closure | corelib | 109.9 → 111.3 (**+1.3 %**) |
| — | `57a20be` | tests for `depth:` (wire identical to the default, the bound is enforced, bad values are refused) | test | — |

After each commit, `dart test` passes all 1471 tests. That covers the shared 131-vector suite
with the skip matrix, the `header_limits` §6.2.1/§6.3 block, strict/chunked invalid UTF-8,
destination and ownership, and alloc-profile. `dart analyze` is clean.

Final round (same A/B round as the "Reproduced" table):
- NEW: 101.9 MB/s
- corelib fixes only: **109.1**
- corelib fixes + generator `depth:`: **111.3 MB/s, 256 k msg/s, 1.88× protobuf**

That recovers 80 % of the loss. The ~2 % still missing is the mandated destination protocol
(cause 3).

## Beyond the regression: a generator win

The generated `onUnsignedArray`/`onSignedArray` copy into the model with
`List<int>.from(values)`, which walks a `_TypedListIterator` (`_ofEfficientLengthIterable`,
`moveNext`, `current`). Together that is ~2.2 k Ir per round trip and was already present in
OLD. An indexed copy lifts the fixed build to **126.2–126.5 MB/s**: +13 %, and 11 % *above*
OLD. The wire is unchanged. Converting the `for (final _v in values)` range checks to indexed
loops as well was neutral (124.7), so that part is not worth doing.

## Fix plan

- **Corelib PR (corelib-dart):** commits 2, 3 (the option) and 4, plus tests. Commit 1 is
  optional cleanup. None of them removes a check. §6.6 still holds, because every piece of
  state is sized at construction and never grown.
- **Generator change (sofabgen Dart backend):**
  1. Emit the schema's static nesting depth on every root and pass it in the one-shot encode.
     Here that is Example → arrays → nested = 2:
     ```dart
     static const int maxDepth = 2;
     Uint8List encode() { final buf = Uint8List(maxSize);
       final e = sofab.Encoder.overBuffer(buf, depth: maxDepth); ... }
     ```
  2. Replace `List<int>.from(values)` with an indexed copy (+13 %). Either emit a private
     helper or host one in the corelib, since AOT inlines across packages:
     ```dart
     List<int> _i64List(Int64List v) { final n = v.length;
       final out = List<int>.filled(n, 0, growable: true);
       for (var i = 0; i < n; i++) { out[i] = v[i]; } return out; }
     ```
- **Environment:** none. SDK, flags and harness are unchanged. The protobuf row is stable
  at 58.7–59.2.
