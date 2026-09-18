# TypeScript / Bun throughput regression (2026-09): analysis and fix plan

Targets: `languages/typescript` (Node 24.21, V8) and `languages/typescript-bun` (Bun 1.4.2, JSC).
They run the same generated code. Corelib-ts is `f4c64c0` and sofabgen is `d865b92`.
Measured on 2026-09-18 on the 16-core WSL2 box with 500k iterations, interleaved A/B,
best of 5–6. Node runs used `taskset -c 2`, which changes nothing for Node. Bun was
measured both pinned and unpinned, because pinning changes the Bun result (see "Environment").
Every variant kept the 434 B `e1733416…9d9d` wire and passed its self-check.

## Reproduced (MB/s)

| variant | Node sofab | Bun sofab (pinned) |
|---|--:|--:|
| OLD: arena `1971be6` + corelib `1eb151d` (the README run) | 74.2 | 77.6 |
| NEW: HEAD + corelib `f4c64c0` | 54.0 (−27 %) | 51.8 (−33 %) |
| protobufjs (the bench is unchanged) | 76.9 | 45.0 |

The timed region is the same in OLD and NEW: `os.reset(); Example.decode(blob).serialize(os)`.
`bench.ts` only moved the `OStream` buffer allocation out of the loop, and the protobuf bench
has no diff at all. The corelib dist/ is rebuilt by `setup.sh` from a stamp, so a stale
dist/ is not the cause here.

## Root causes (bisected across gen×corelib pairs, then ablated end-to-end)

These pairs build and pass: 1971be6/749143f → 322feac/{6112092…d49d25c} → 5b1d21a/b51cf6b →
8869e04/{2c02405…f4c64c0}. Node / Bun (MB/s): 74.7/76.0 → 67.8/63.6 (at 6112092; 9bcae95 brings
Node back to 70.4) → 70.6/64.7 → 55.7/52.7. The corelib commits 354b845, 2fc2933, 6b45d0e and
e24d92f are flat.

1. **Typed-array destinations: 590fd3f + 2c02405…f4c64c0 with the matching sofabgen output.**
   This step costs −21 % on Node and −18 % on Bun. Four pieces:
   - **(a) Generated code allocates about 20 empty typed arrays per decode.** These are the
     message defaults (`u8 = new Uint8Array(0)` …) and the visitor's placeholder fields and
     targets. Each one is replaced before it is read. Ablation (shared module-level
     zero-length sentinels): **54.2 → 60.0 MB/s (+10.8 %)**.
   - **(b) The fp32 destination touches `.buffer` on both sides.** Decode passes
     `bits: new Uint32Array(m.buffer, …)`, and encode (`packFp32Array`, c9fdc70) builds a
     `Uint32Array` view plus a `DataView` for 5 elements. Reading `.buffer` moves a small
     on-heap typed array's storage off-heap. Fix: corelib `76f1cba` plus the generator passing
     `f32`: **60.4 → 65.5 (+8.4 %)**.
   - **(c) `resolveTarget` goes megamorphic.** A single site sees all six narrow typed-array
     maps, so `d.length`/`d.constructor` fall back to generic accessor calls. On top of that
     come a `Map` probe keyed by the constructor and two `instanceof` checks, once per array
     (10 arrays per message). Skipping the check entirely would be worth +6.5 %. The fix,
     corelib `c944b0a`, **keeps every check: 66.0 → 69.2 (+4.8 %)**.
   - **(d) Allocating the typed arrays themselves (`new Int8Array(count)` ×8).** This is the
     cost of the new API. Pooling them (a semantics-breaking ablation) would gain +3.4 % on
     Node and +7.7 % on Bun. **Not fixed.**
2. **6112092, the push-visitor redesign plus the regenerated visitor.** It costs −9 % on Node
   (9bcae95 recovers 4 of those points) and **−17 % on Bun**. JSC pays more for the `run`
   state machine, `varintFull` and the per-element visitor dispatch than for the old pull
   cursor. This is architectural, and no single hot spot stands out in the Bun profile.
   One small part is the `DataView`-based `fp32FromBits`/`fp64FromBits`. Corelib `e9c5740`
   switches them to same-width typed aliases: **Bun +2.8 %**, Node +0.8 % (noise).
3. **Bun 1.3.14 → 1.4.2 (environment).** The Dockerfile installs whatever Bun is current, so
   the image picked up 1.4.0 (released 2026-08-20) after the 2026-08-18 README run. Unpinned, the way
   the runner runs it: protobufjs drops 53.0 → 33.0 MB/s (−38 %) and NEW sofab drops
   52.6 → 44.3 (−16 %). That explains why *both* Bun columns fell. System time goes
   0.9 s → 3.3 s: Bun 1.4 marks in parallel on all 16 cores. With `taskset -c 2` the gap
   shrinks to protobuf −14 % and sofab ≈0. With `BUN_JSC_numberOfGCMarkers=1`, protobuf is
   47.8 and sofab is 53.9 (fixed: 66.6).

Checked and ruled out:
- Harness or timed-region changes.
- Deopts: `--trace-deopt` is clean on the hot functions.
- UTF-8 double validation: unchanged since OLD.
- A stale dist/.

## Fixes, measured end-to-end against unmodified NEW

corelib-ts branch `perf/arena-regression-2026-09` (local, not pushed): `76f1cba`, `c944b0a`,
`e9c5740`. The full vitest suite (2589 passed / 4 skipped, including the 131-vector corpus,
the skip matrix, caps and strict UTF-8) and `tsc --noEmit` pass after each commit. Three
tests that documented the old behaviour were updated: "f32 quiets an sNaN" and "a
Float32Array encode always allocates a view + DataView". The `f32` destination is now
bit-exact for every NaN, and encode allocates one view only when a NaN is present.

| variant | Node MB/s | Bun MB/s (pinned) |
|---|--:|--:|
| NEW | 54.0 | 51.8 |
| corelib fixes only | 57.5 (+6 %) | 54.3 (+5 %) |
| generator fixes only | 59.4 (+10 %) | 53.6 (+3 %) |
| **both** | **69.4 (+28.5 %)** | **62.4 (+20.5 %)** |
| OLD, for reference | 74.2 | 77.6 |

The two halves reinforce each other: once (a) removes the allocation noise, the view,
materialisation and megamorphic costs dominate. On Node the combined result is 0.90×
protobuf (NEW is 0.70×).

## Fix plan

- **Corelib PR (corelib-ts):** the three commits as they are. None of them removes a check.
- **Generator change (sofabgen TS backend):**
  - Emit one module-level zero-length instance per typed-array type
    (`const _E_Uint8Array = new Uint8Array(0)`). Use it for every message default and every
    visitor placeholder and target field (`{ typed: _E_Uint8Array, … }`). A zero-length typed
    array cannot be written through, so sharing it is safe. **+10.8 %.**
  - For a `Float32Array` member, hand over `{ f32: this._aNFp32 }` instead of
    `{ bits: new Uint32Array(m.buffer, m.byteOffset, m.length) }`. Emit this only together
    with the corelib `76f1cba` requirement; on older corelibs `f32` quiets an sNaN.
- **Environment:** pin Bun in `.devcontainer/Dockerfile`
  (`curl -fsSL https://bun.sh/install | bash -s bun-v1.3.14`, or a vetted 1.4.x) and track it in
  `languages/versions.sh`. Alternatively, set `BUN_JSC_numberOfGCMarkers=1` in
  `typescript-bun/bench.sh` for both impls, with a justification comment. That is a portable
  GC knob, not CPU pinning, and it is worth +45 % for protobufjs and +22 % for sofab on this box.
- **Not recovered:**
  - Node: about −6 % from the visitor redesign plus the typed-array allocation (1d).
  - Bun: about −20 %, mostly the redesign on JSC (2) and 1d. Recovering it would need a
    Bun-specific profile of `run`/`varintFull`.
