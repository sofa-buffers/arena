# Go throughput regression (2026-09): analysis and fix plan

Target `languages/go`, corelib-go `4b0d669`, sofabgen `0.0.0-20260918072500-d865b9213550`.
Measured 2026-09-18 on the 16-core WSL2 box: `taskset -c 2`, `GOGC=400 GOMAXPROCS=1`
(the same as `bench.sh`), 1M iterations, interleaved A/B, best of 6. Every variant
kept the reference wire (434 B, `e1733416…9d9d`) and passed its self-check.

## Reproduced

| variant | sofab MB/s | msg/s | vs protobuf (msg/s) |
|---|--:|--:|--:|
| OLD: arena `1971be6` + corelib `eff4c9c` (the README run) | 157.7 | 363 k | 1.25× |
| NEW: HEAD + corelib `4b0d669` | 121.0 | 279 k | 0.96× |
| protobuf (unchanged) | 143.8 | 291 k | — |

That is **−23 %** (the README had 162.9, and 157.7 is the same result on today's box).
The timed loop (`sofab/main.go`), `bench.sh`, `setup.sh` and the Go toolchain are the
same for both. Only the generated callgrind `harness/` changed, and it is not timed.
So the whole loss comes from corelib and codegen. Split with `go test -bench` (ns/op):
round trip 2900 → 3760, decode 1960 → 2540, encode 800 → 1010 (plus 1 KB and 1 alloc
per op).

## Root causes (bisected, then ablated end-to-end)

1. **Encode, `db4933b`** ("no allocation after construction"). The lazy-sequence
   `pending` stack is now sized to the full `MaxDepth`: 255 IDs, 1 KB. Since `11ff381`
   that is its own allocation, and the generated one-shot `Encode()` builds a fresh
   Encoder for every message. Encode-only bisect: flat at 820 ns up to `6e73e4c`, then
   1010 ns at `db4933b`, with B/op going 960 → 2000. With GC pressure included, the
   round trip loses 330 ns.
2. **Decode, `bdd5f8b`** ("one push state machine") together with the generator's move
   to per-element callbacks. The old generated code still decodes at 1980 ns on
   `42c8c09`. The new code decodes at 2530 ns from `3d90704` onward, and later commits
   are flat. In the profile, the push machine sends **every varint through two calls**
   (`varint` → `uvarintFast`) and a round trip through `d.acc`/`d.nb`. The old cursor
   read the one-byte case inline (`uvarint1`), and a one-byte varint is nearly every
   header, count and element in this message.
3. **Collector growth** (codegen now uses the corelib `StringSeq`). The gap-filling
   `append` grows the count-5 `string_array` 1→2→4→8 on every decode: 4 allocations
   and 3 copies. `growslice` is about 10 % of decode.
4. Minor: `cur()` runs once per delivered field and costs a skip test plus a
   bounds-checked stack index.

Checked and ruled out:
- **The Decoder's 4.4 KB parse-stack zeroing.** Shrinking the stack to 16 measured
  153.8 vs 154.1 MB/s, which is noise.
- **UTF-8 validated twice per round trip** (decode §6.4 plus the producer check in
  `WriteString`). Both checks are mandated and both already existed in OLD.
- **A bulk array-run callback.** Handing a landing-zone slice through an interface
  makes it escape, which would push the Decoder onto the heap. Not pursued.

## Fixes, measured end-to-end against unmodified NEW

These are corelib-go commits on the local branch `perf/arena-regression-2026-09`
(not pushed). Each commit passes `go test ./...`, `-tags sofab_no_strict_utf8` and
`-race`, including the 131-vector shared corpus, the skip matrix, header limits and
strict UTF-8.

| # | change | kind | MB/s (step) |
|---|---|---|--:|
| 1 | `d52a846` single-byte varint read inline at every `run`/`arrayElements` call site; `readVarintSlow` handles multi-byte, resumed and end-of-chunk varints | corelib PR | 121.2 → 133.1 (**+9.8 %**) |
| 2 | `135e231` `WithMaxDepth(n)` encoder option: the pending stack is sized at construction to the schema depth, inline in the Encoder for n ≤ 8, and opening sequence n+1 returns `ErrArgument`. Options are applied straight into the Encoder, so passing one allocates nothing | corelib PR + **generator** | 133.1 → 141.0 (**+5.9 %**) |
| 3 | `13911fc` current visitor cached in `d.top` | corelib PR | 141.7 → 144.8 (+2.2 %, close to noise) |
| 4 | `116a53e` `reserveRows`: collector destinations are reserved once to the **schema** count (≤ 64), never from a wire number | corelib PR | 144.8 → 154.3 (**+6.6 %**) |

Combined results (same A/B round as the table at the top):
- **All four fixes: 154.5 MB/s, 356 k msg/s, 1.22× protobuf msg/s.** That is +28 % over
  NEW and −2 % from OLD.
- Corelib fixes alone, without the generator change: 141.0 MB/s.
- Split after the fixes: round trip 2980 ns, decode 2050 ns, encode 830 ns (2 allocs).

## Fix plan

- **Corelib PR (corelib-go):** fixes 1, 3 and 4 as they stand, plus fix 2's
  `WithMaxDepth` option. None of them removes a check. Fix 2 keeps §6.0.1: the stack is
  sized at construction and never grown.
- **Generator change (sofabgen Go backend):** emit the schema's static nesting depth
  and pass it on every one-shot encode:
  ```go
  const ExampleMaxDepth = 2 // deepest Serialize nesting (Example→arrays→nested)
  var _exampleEncOpts = []sofab.Option{sofab.WithMaxDepth(ExampleMaxDepth)}
  // in Encode(): sofab.NewEncoderBuffer(buf, 0, _exampleEncOpts...)
  ```
  Use a package-level slice so the call site allocates nothing. Worth +6 to +10 %
  together with fix 2.
  Optional: `BeginSequence` for a bounded string/blob array could pre-size
  (`make([]string, 0, 5)`) instead of `[:0]`, which would make fix 4 redundant for
  generated code.
- **Environment:** nothing to change. The flags, runtime knobs and toolchain are the
  same in OLD and NEW.
- **Not recovered (about 2 %, within run-to-run spread):**
  - Per-element array callbacks (50 interface calls).
  - `PayloadAcc.Take` (inline cost 125) not inlined.
  - `StringSeq` re-checking `overIndex`/`overLen` in `String` after `FixlenBegin`.
