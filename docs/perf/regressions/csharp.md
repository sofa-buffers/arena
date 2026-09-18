# C# throughput regression (2026-09): the encoder grew by 1020 bytes

Target: `languages/csharp`, with corelib-cs `da3d808` and sofabgen `0.0.0-20260918072500-d865b9213550`.
Runtime: .NET 9.0.20 with the `bench.sh` GC knobs (workstation, non-concurrent, 64 MB gen0).
Box: 16-core WSL2, measured 2026-09-18. Each run did 2M iterations, unpinned like `bench.sh`,
in 7 interleaved rounds. All 185 runs emitted the reference wires (sofab 434 B `e1733416…`,
protobuf 494 B `e8d391d9…`), and every self-check passed.

## Reproduced: the regression is real, not noise

The table comes from one interleaved series: best of 7, median in brackets.

| variant | sofab MB/s | msg/s | vs NEW |
|---|--:|--:|--:|
| OLD: arena `1971be6` generated code + corelib `61a80ff` (tip on 2026-08-19) | 207.5 (204.8) | 478 k | +7.7 % |
| NEW: HEAD generated code + corelib `da3d808` | 192.7 (192.0) | 444 k | — |
| protobuf control (unchanged) | 126.7 (123.9) | 256 k | |

OLD is ahead of NEW in all five series I ran, by 6.8–7.7 % on best-of and 5.5–8.8 % on
median. The box's round-to-round spread is about ±2 %, so this gap is real. OLD built against
corelib `2770d61` (before `61a80ff`) measured the same as OLD, within noise (206.8 vs 208.7).

**Harness and environment:** `Bench.cs`, `bench.csproj`, `setup.sh` and `bench.sh` are
byte-identical to `1971be6`, so the timed region did not change. Only `sofab/gen/Message.cs`
changed. The Dockerfile installs `--channel 9.0` unpinned, so the runtime patch level may have
moved since August. I could not A/B that, and it is not needed to explain the loss.

## Root cause: corelib `8b678c6` (#100, "size the encoder's fixed state at construction")

I bisected by ablation, with the real bench and 7 interleaved rounds:

| variant | best / median MB/s |
|---|--:|
| OLD generated code + corelib `61a80ff` | 205.5 / 201.7 |
| OLD generated code + corelib `8b678c6` | **195.1 / 191.0** ← the whole step |
| OLD generated code + corelib `da3d808` (`Status` patched out) | 194.3 / 191.6 |
| NEW generated code + corelib `da3d808` | 192.2 / 191.2 |
| NEW, with only `[InlineArray(MAX_DEPTH)]` changed to `[InlineArray(8)]` | 205.0 / 200.5 |

- `8b678c6` moved the pending run of held-back sequence ids into an `[InlineArray(MAX_DEPTH=255)]`
  inside `OStream`. That makes every encoder 1020 bytes larger, and the allocator zeroes all of
  it. Generated `Encode()` runs `new OStream(buf)` once per message. The allocation counter
  (`GC.GetAllocatedBytesForCurrentThread`) shows encode going from **544 to 1536 B/op**.
  The doc comment says the shape "measured cheapest under run_callgrind.sh". Callgrind counts
  instructions, so it cannot see the extra 1 KB of zero-fill and the gen0 churn that comes
  with it.
- **Suspects cleared.** `61a80ff` did not cost inlining: the JIT disasm shows
  `PayloadAcc.String`, including its cap check, inlined into `ExampleVisitor.String` across the
  assembly boundary. `Utf8.Decode` is a call, and so was the old generated `_Utf8`, because both
  contain try/catch. `c3018a2` and `7ff1547` add only a compare each. `bc16a5d` renames
  `Status` and leaves the hot path alone. Together with the regenerated `Message.cs`, these
  account for about 1 %, which is the per-decode `new PayloadAcc()` (+32 B/op on decode).
- dotnet-trace (sampled) was not usable. Every sample collapses into `UNMANAGED_CODE_TIME`
  with broken stacks, the same problem the July analysis hit. I attributed cost by ablation
  and allocation counting instead.

## Fixes, measured end-to-end (same final series as the first table)

| # | change | where | best / median MB/s | gain vs NEW |
|---|---|---|--:|--:|
| A | `OStream.Reset(buffer, offset)`. Generated `Encode()` keeps a `[ThreadStatic] OStream` next to `_encScratch` and resets it instead of constructing one. Encode drops to 464 B/op. | corelib + generator | 204.6 / 201.5 | **+6.2 %** |
| B | A, plus lazy `PayloadAcc`. The single-chunk case calls `PayloadAcc.CheckStringLength`/`CheckBlobLength` + `Utf8.Decode`/copy directly, and `pay ??= new PayloadAcc()` happens only on the split path. | generator | 206.0 / 203.6 | +6.9 % (B over A ≈ +1 %, borderline) |
| C | B, plus the wrapper-array `List<T>` presized to the schema count (`string_array = new(5)`), which removes two `AddWithResize` growths per decode. Decode drops 1496 → 1416 B/op. | generator | **212.6 / 209.6** | **+10.3 %**, 2.5 % above OLD |

With C the ratio is 1.68× vs protobuf in this series (NEW: 1.52×). The corelib suite on the
perf branch passes **1469/1469 on net9.0 and net10.0**. That run covers the shared vectors,
the skip matrix, §6.2.1 header limits, §6.3 terminal refusal and strict UTF-8, plus six new
`OStreamResetTests`, among them one checking that reuse performs zero allocations.

## Fix plan

- **Corelib PR (corelib-cs):** `74e0e16` on the local branch `perf/arena-regression-2026-09`
  (not pushed). It adds `OStream.Reset(byte[] buffer, int offset)`, which re-installs the buffer
  (with the same `CheckBuffer` rules), zeroes `_depth` and `_nPending`, and keeps the sink. §6.6
  still holds: the fixed state is still laid down once, at construction. Worth +6.2 %, but only
  together with the generator change below.
  - A corelib-only alternative would be shrinking the inline run. It is not viable, because
    ids are full `int` and §6.6 forbids growing the run after construction.
- **Generator change (sofabgen C# backend):**
  1. Emit a reused per-thread encoder. It has the same re-entrancy caveat as `_encScratch`.
     ```csharp
     [ThreadStatic] private static OStream _encStream;
     var os = _encStream; if (os == null) _encStream = os = new OStream(buf); else os.Reset(buf, 0);
     ```
     Without the new API, a fallback is to call `os.BufferSet(buf, 0)` on the cached stream and
     drop it (`_encStream = null`) in a catch. After a successful `Serialize` the depth and
     pending counts are already 0. This fallback was not measured.
  2. Emit the one-shot string/blob path inline and create `PayloadAcc` lazily (≈ +1 %).
  3. Emit `new(<count>)` for bounded wrapper-array `List<T>` fields (+3 %).
- **Environment:** nothing to change. For reproducibility, consider pinning the .NET 9 patch
  level in the Dockerfile.

Scratch builds and the A/B runner live in `/tmp/claude-0/regress/csharp/` (`ab.sh`, variants
`old61/new/fixA/fixB/fixC`).
