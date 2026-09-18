# Zig throughput regression (2026-09-18)

Reproduced on this box (Ryzen 7 5700U, WSL2, zig 0.16.0, `--release=fast`, `taskset -c 2`, best
of 7 interleaved rounds, `BENCH_ITERS=2000000`, sha256 gate checked on every run). **OLD** = arena
@1971be6 generated code (last regen `9d30a23`/`f436ff1`) + corelib-zig `6e08a48` (the tip on
2026-08-16). **NEW** = HEAD + corelib-zig `1eb2e69`. The driver (`bench.zig`, which uses a
`FixedBufferAllocator` rewound once per iteration) and `build.zig` did not change. Only
`gen/src/{message,main}.zig` differ.

| variant | MB/s | vs NEW |
|---|--:|--:|
| OLD | 474.3 | +2.1 % |
| **NEW** | **464.6** | — |
| NEW, ablation: `_take(..., borrow = true)` | 481.8 | +3.7 % |
| NEW + validate-before-copy (generator fix, below) | 467.4 | +0.6 % |
| protobuf (zig-protobuf, same binary for both) | 266.7 | |

**The −2.1 % is real.** Spreads are under 0.5 %, and the number reproduces across 5 sessions
(OLD 474.2–475.0, NEW 464.4–464.6) and under 0–2.9 KB of environment padding.

## Root cause: the generator's "a decoded message owns its bytes" change, not the corelib

The generated `decode()` used to **borrow** every string/blob from the input buffer. Now it
copies each one into the caller's allocator. Every string arm goes through
`_take → sofab.PayloadAcc.take(alloc, …, borrow = false) → alloc.dupe`, which is 7 allocations
plus 7 small `memcpy` calls per message (6 strings + 1 blob). The generated doc comment gives
the reason: the message's lifetime must not depend on the entry point.
- **Ablation:** in NEW, pass `true` instead of `false` in `_take`. The result is 481.8, which is
  **above OLD**. The owning copy costs 3.5 %, and everything else in NEW together is +1.6 %.
- **Callgrind** (Ir per round trip, `-Dcpu=x86_64_v3` build): OLD 11,996, NEW 12,041, borrow
  11,669. NEW adds `FixedBufferAllocator.alloc` (+144 Ir, reached through the
  `std.mem.Allocator` vtable) and `memcpy` (+131 Ir) compared with borrow.

**corelib-zig is neutral at HEAD.** OLD gen (`utf8_valid` → `utf8Valid` only) against corelib
commits: `6e08a48` 475.0 · `1d66e07` 475.3 · `94349e4` 461.5 · `3a28b07` 455.6 · `dd335a1`
469.1 · HEAD 472.7 (−0.5 %). The dip at `94349e4` adds only 6 Ir per iteration (one bound compare
on 2 fixlen arrays), so it is a layout effect. The receiver-cap plumbing of `3a28b07` costs about
1 %, and both dips are recovered by `e95a97e`/`dd335a1`. `1d66e07` (FixedArray, CollectingSink)
and `a0a6711` (`at`) cost nothing.

## Prototypes (hand-edited `gen/src/message.zig`, measured end-to-end)

| prototype | result | verdict |
|---|--:|---|
| `_takeStr`: run `utf8Valid` on the **source** slice, then `dupe`. An invalid string is never allocated, and the validator does not re-read bytes the copy just stored. | 467.4 (+0.6 %, stable across pads) | keep, small |
| One slab of `data.len` bytes per `decode()`, then bump-copy each payload (1 vtable alloc instead of 7) | 467.0 (+0.5 %) | marginal. The cost is the copies, not the allocator calls |
| `dupe` the whole input once, then borrow from that copy | 407–472 **for the same binary**, depending on the build and run | rejected: the 434-byte `memcpy` is alignment-sensitive |
| corelib: one-pass Table 3-7 UTF-8 validator replacing ASCII-prefix + `std.unicode.utf8ValidateSlice` | 457.0 (−1.6 %, +140 Ir/iter) | rejected: std's validator is already faster. Reverted, and nothing committed to corelib-zig |

## Fix plan

| where | change | measured gain |
|---|---|--:|
| **generator (zig backend), design call** | Give the one-shot path an explicit borrowing entry point, e.g. `decodeBorrowed(alloc, data)` (strings/blobs are slices of `data`; the caller keeps `data` alive), or a cfg option that restores borrowing for `decode()`. Keep owned `decode()` as the safe default. The arena's zig driver would call the borrowing form. Every other target copies strings, so whether that is fair is Andreas's decision. | **+3.7 %** vs NEW (481.8, +1.6 % above OLD) |
| **generator (zig backend)** | Emit the string arms as validate-then-copy (`_takeStr` above) instead of copy-then-validate. | +0.6 % |
| corelib-zig | none. HEAD is neutral against OLD, and no corelib change was kept (branch `perf/arena-regression-2026-09` deleted: nothing to commit). | — |
| environment | none | — |

If the owned semantics stay, the zig row keeps most of the −2 %. The mandated copy costs
3.5 %, and only about 0.6 % of that can be recovered without borrowing.

Conformance: `zig build test` in corelib-zig passes: 106 unit tests and 97 conformance tests,
including the 131-vector suite, skip matrix, header_limits §6.2.1/§6.3 and strict UTF-8. The
rejected validator also passed an exhaustive 1/2/3-byte equivalence test against std. The wire
is unchanged: 434 B, `e1733416…29d9d` on every measured run, and the self-check passes. Scratch
builds are under `/tmp/claude-0/regress/zig/` (`abl-borrow`, `fix-valfirst`, `fix-slab`,
`fix-dupe1`, `bisold-*`).
