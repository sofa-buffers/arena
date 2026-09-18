# Rust throughput delta: rust, rust/heapless, rust-embedded (2026-09-18)

Reproduced on this box (Ryzen 7 5700U, WSL2, `taskset -c 2`, best of 7–9 interleaved rounds,
default `BENCH_ITERS`, sha256 gate checked on every run, rustc 1.98.1). **OLD** = arena @1971be6
generated code (last regen `f436ff1`, 2026-08-16) + corelib-rs `a70386d` / corelib-rs-no-std
`8a96d7a` (the tips on that date). **NEW** = HEAD + corelib-rs `29311a5` / corelib-rs-no-std
`311960d`. The drivers, `setup.sh` flags and both `[profile.release]` blocks did not change
(`git diff 1971be6 HEAD -- languages/rust languages/rust-embedded` touches only `gen/`).

| row | OLD MB/s | NEW MB/s | Δ | with generator fixes |
|---|--:|--:|--:|--:|
| rust / sofab | 300.6 | 382.8 | **+27 %** | **418.2 (+9.2 %)** |
| rust / sofab-heapless | 476.7 | 482.3 | +1.2 % (noise) | 485.3 (+0.6 %), 1 → 0 allocs/decode |
| rust / protobuf (prost) | 248.3 (code unchanged, one binary) | | — | — |
| rust-embedded / sofab | 181.3 | 176.8 | −2.5 % (median −4.4 %) | no source fix, see 3. |
| rust-embedded / micropb | 125.1 (code unchanged, one binary) | | — | — |

**heapless has no regression.** Three separate 7-round sessions give NEW +1.2 %, +1.6 % and
+2.8 % over OLD. The same holds with rustc 1.97.1, the stable compiler on 2026-08-16
(476.8 → 486.4), so the compiler is not a factor. The README's 511.9 does not come from the
run in `results/RESULTS.txt` at the same commit (that file says 497.88). The README "−6 %" is
run-to-run spread plus a stale table.

## Root causes (ablated end-to-end)

**1. The +27 % on rust/sofab is `reserve_exact(count)` in the generated `array_begin`.**
Removing the 10 `reserve_exact` calls from NEW gives 307.0. Adding them to OLD gives 384.9,
which equals NEW. The corelib swap (OLD gen against corelib-rs HEAD, `5ba324e` PayloadAcc,
`7599f9a` `Result<Status>`) gives 312.8, within the spread, so it is neutral. Mechanism:
`Vec::push` from empty allocates capacity 4, then reallocates to 8 at the 5th element. That
is a malloc plus a realloc for each of the 9 non-`u8` arrays. Pre-sizing from the wire count
turns this into one malloc per array. The count is already checked against the schema
`count` (≤ 5) first, so this adds no allocation amplification.
**Apply elsewhere:** every target whose generated decode fills a *growable* array element by
element should pre-size from the checked count: C# `List<T>(count)`, Java `ArrayList`, Go
`make(..., 0, count)`, Dart, Kotlin, and C++ `std::vector::reserve`.

**2. What rust/sofab still pays: 19 heap allocations per decode.** Measured with valgrind
(`total heap usage` delta per iteration). Two of them are not needed:
- `string_array` (`Vec<String>`) grows with `while len <= id { push(Default) }`: 0 → 4 → 8,
  which is a malloc plus a realloc. The callgrind output still shows `RawVecInner::finish_grow`
  and `realloc`.
- The visitor's `stack: Vec<_Loc>` allocates at the first `sequence_begin`. This happens in
  **both** std profiles. So the heapless row, which is documented as "a decode allocates
  nothing", does 1 malloc and 1 free per decode.

**3. rust-embedded −2.5 %: a real wall-clock change, but not extra work.** Callgrind Ir per
round trip: OLD 24,841, NEW 25,702. The +861 is one 741-byte `rep stosb` per decode:
`PayloadAcc<732>::new()` (corelib-rs-no-std `78616c6`) has to write `[0; N]` because the crate
is `forbid(unsafe_code)`. The old `heapless::Vec` did not write the buffer. Removing that cost
does not bring the time back, though:
- OLD gen on corelib-no-std HEAD runs at 181.3, the same as OLD. So `be977b9`, `2e3d343` and
  `8fe3712` are neutral.
- NEW gen with PayloadAcc replaced by the old `heapless::Vec` code has the same Ir as OLD
  (24,835) but runs at 168.9, which is slower than NEW.
- A lazy accumulator (`buf: Option<[u8; N]>`) also brings Ir back to OLD (24,983) but runs at
  173.0 vs 177.4, and it costs **+240 B `.text` on rust-cortex-m** (+88 B on rust-riscv).
  **Rejected.**

The ranking stays the same when the stack is shifted with 0–2.9 KB of environment padding and
under `-align-all-functions=6`. This is a code-placement effect of the regenerated code in an
`opt-level=z` binary: builds with the same instruction count differ by 3–6 %. There is no
source-level fix for it.

## Fix plan

| where | change | measured gain |
|---|---|--:|
| **generator (rust, `allow_dynamic: true`)** | For a wrapper string/blob array, reserve the schema count once, on the first element: `if self.m.string_array.capacity() == 0 { self.m.string_array.reserve_exact(5); }` before the `while … push(Default)`. The size comes from the schema bound, not from the wire. | rust/sofab **+7.9 %** (382.8 → 413.0) |
| **generator (rust, both std profiles)** | Emit the decode stack as `stack: [_Loc; D+1], sp: usize` (D = the schema's maximum sequence depth, here 2) instead of `Vec<_Loc>`. Push: `if sp == D+1 { dead += 1; return }` (that level is a skipped subtree anyway). Pop: `if sp > 0 { sp -= 1; stack[sp] } else { Root }`. `Decoder::feed` copies the array instead of calling `mem::take`. rust-embedded already uses a `heapless::Vec` stack. | sofab +1.3 % on top (418.2); heapless +0.6 % (485.3) and **0 allocs/decode** (was 1) |
| corelib-rs / corelib-rs-no-std | none. The lazy `PayloadAcc` removes the memset but gains no time and grows the bare-metal footprint. | — |
| environment | none. The rust-embedded delta is code placement at `-Oz`. The heapless delta is noise. | — |

Hand-edited scratch copies of `gen/src/message.rs` were measured: `fix-strarr`, `fix-both`
and `hl-fix-stack` under `/tmp/claude-0/regress/rust/`. The wire is unchanged: 434 B,
`e1733416…29d9d` on every run, and the self-check passes.

Conformance: corelib-rs and corelib-rs-no-std are unchanged, so no corelib branch is kept. The
rejected lazy `PayloadAcc` prototype passed the no-std suite before it was discarded: 262 tests,
including the 131-vector file with its skip matrix and header_limits, plus `cargo fmt --check`
and the `thumbv7em-none-eabihf` no_std build. clippy is not installed on this box.
Bare-metal footprint at HEAD (unchanged, since nothing was committed): rust-cortex-m sofab
text 6,660 B, rust-riscv 7,056 B.
