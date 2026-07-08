# CLAUDE.md — SofaBuffers Arena

## What this repo is

A **multi-language benchmark arena**: it builds SofaBuffers and one or more
protobuf-family baselines against **one identical message with one identical
payload** and measures who is leanest and fastest, split into two categories so
opponents always play in the same league:

- **maxspeed** — SofaBuffers corelib vs Google protobuf runtime, per language
  (cpp, rust, go, csharp, java, typescript, typescript-bun, python). Ranked by
  encode+decode **throughput (MB/s)**. Everything is built/tuned for speed.
- **embedded** — SofaBuffers embedded corelibs (`corelib-c-cpp`,
  `corelib-rs-no-std`) vs footprint-oriented protobuf libraries (nanopb,
  EmbeddedProto, micropb; protobuf-c as reference). Ranked by **code footprint**.
  Everything is built for size (`-Os` / `opt-level=z`).

Never mix the categories: a throughput-tuned corelib is only compared against a
throughput-tuned protobuf runtime, an embedded corelib only against an embedded
protobuf library. `scripts/run_benchmark.sh` is the single entry point; it
builds, runs, gate-checks and prints both result tables.

## The prime directive: fairness

Every change must preserve these invariants (see `docs/BENCH.md`, the contract):

1. **One message, one payload.** `schema/message.sofab.yaml` and
   `schema/message.proto` mirror each other field-for-field. The field values
   every target fills are canonical: `schema/STATE.md` (human) /
   `schema/state.json` (machine). No target may invent, reorder or skip values.
2. **Byte-identity gate.** All `impl=sofab` targets must emit the identical
   **434-byte** wire, all protobuf-family baselines the identical **494-byte**
   wire. Reference SHA-256s live in three places that must stay in sync:
   `docs/BENCH.md`, `schema/STATE.md`, and `REF_SOFAB_SHA`/`REF_PROTO_SHA` in
   `scripts/run_benchmark.sh`. The runner fails a target whose SHA drifts.
3. **Identical optimization per row.** Within a target, SofaBuffers and its
   baseline(s) get the **same compiler flags, same runtime tuning, same timing
   method, same iteration count**. If you tune one side, apply it to the other
   or don't apply it at all. Runtime tuning must be **portable** — never pin a
   CPU/ISA level (`-march=native` is fine because it adapts per host and the
   arena rebuilds on each host).
4. **Only encode+decode is timed.** Warm-up + self-check (one round-trip,
   capture wire size + SHA-256, assert decoded message re-encodes to identical
   bytes, exit non-zero on failure) happens **before** the timed loop.
   Construction, JSON/state parsing and I/O are never counted. Buffers/decode
   targets are hoisted out of the loop where the language allows.
5. **Uniform machine-readable output.** Each target prints only these to stdout
   (everything else goes to stderr):

   ```
   BENCH     lang=<l> impl=<i> serialized_bytes=<n> iters=<n> cpu_time_s=<f> throughput_mbs=<f> sha256=<hex>
   FOOTPRINT lang=<l> impl=<i> text=<n> rodata=<n> data=<n> bss=<n>
   ```

6. **MB/s is within-row only.** Different runtimes (JIT/VM/native) make
   cross-row speed comparison meaningless; the cross-row columns are wire size
   and the per-row ratios. Throughput is reported best-of-5 (`RUNS=5` default).

## The message and payload

- `schema/message.sofab.yaml` — SofaBuffers definition, compiled by `sofabgen`.
- `schema/message.proto` — proto3 twin (`package fullscale`, message
  `FullScaleExample`), compiled by `protoc` / each baseline's own generator.
- Mapping rules between the two: proto field numbers 1..8 ↔ sofab ids 0..7
  (−1 offset on scalars/struct members); container fields keep the same number
  (`nested`=10, `arrays`=100, `string_array`=200); proto `repeated` ↔ sofab
  fixed `count: 5`; proto has no narrow ints, so u8/u16→`uint32`, i8/i16→`int32`;
  sofab strings carry `maxlen` for fixed-capacity embedded storage.
- Payload: every scalar width, floats incl. ±FLT_MAX/±DBL_MAX, UTF-8 strings
  incl. one **empty** string (exercises sparse default omission), raw bytes,
  eight 5-element numeric arrays, nested structs — see `schema/STATE.md`.
- Natively-filled targets (C/C++ benches, footprint drivers) hardcode the fill
  mirroring STATE.md; managed targets load `state.json` (env `STATE_JSON`)
  **outside** the timed region. Either way the gate catches any drift.

**If you change the message or the values:** update both schema files + STATE.md
+ state.json + every hardcoded fill (c-embedded, cpp, footprint drivers,
nanopb `message.options` constraints), re-run everything, then update the
reference sizes/SHAs in `docs/BENCH.md`, `schema/STATE.md`,
`scripts/run_benchmark.sh`, and the README prose. This is deliberate friction —
the wire references are the fairness anchor.

## How the runner works

`./scripts/run_benchmark.sh` (env: `LANGS`, `RUNS` (default 5, best-of),
`BENCH_ITERS`, flag `--no-setup`):

- For each name in `LANGS` it reads `languages/<name>/meta`
  (`category=maxspeed|embedded`, `metric=throughput|footprint`), runs
  `setup.sh` (logs → `results/raw/<name>.setup.log`), then runs `bench.sh`
  `RUNS`× (stdout → `results/raw/<name>.out`), parsing every
  `BENCH`/`FOOTPRINT` line and keeping the **max** throughput per impl.
- Impls are auto-discovered from the emitted lines — there is no impl registry;
  a new baseline shows up by simply printing its lines.
- Host embedded targets emit BENCH + FOOTPRINT (their throughput gets its own
  table; the host object-sum FOOTPRINT is collected but no longer tabulated).
  Bare-metal targets are **build-only** — FOOTPRINT only, binaries never run.
  Footprint ranking = `.text + .rodata + .data` (flash); static-RAM = `.data + .bss`.
- Output: both tables → stdout and `results/RESULTS.txt` (committed). The
  README's Results section (between `<!-- RESULTS:BEGIN/END -->`) is refreshed
  from it manually — keep them consistent.

## Repository layout

```
schema/                 message definitions + canonical state (single source of truth)
docs/BENCH.md           the benchmark contract (READ FIRST before touching targets)
docs/perf/bottlenecks.md  perf-tuning history/methodology (codegen fixes now upstream)
languages/<target>/     meta + setup.sh + bench.sh (+ footprint.sh) + one dir per impl
languages/common/       shared sha256.c/h for C/C++ targets
scripts/bootstrap.sh    pins SOFABGEN_VERSION, fetches sofabgen + clones corelibs
scripts/run_benchmark.sh  the single entry point / aggregator
.devcontainer/          full multi-language toolchain image (the ONLY supported env)
tools/                  sofabgen binary + python venv   (bootstrapped, gitignored)
vendor/                 corelib clones + nanopb/EmbeddedProto (gitignored)
results/RESULTS.txt     committed report; results/raw/ gitignored
generator/, old-repo/   reference clones, gitignored (sofabgen source; legacy C/C++ arena)
```

Committed vs generated: **generated protoc/sofabgen sources ARE committed** (the
repo stays browsable without regen; `setup.sh` regenerates idempotently) —
**except** EmbeddedProto output (GPLv3: generated `gen/` is gitignored, the
library is fetched build-time only, never redistributed). Heavy build output
(`target/ bin/ obj/ build/ node_modules/ dist/`, bench binaries) is gitignored.

## Toolchain & environment

- Work happens inside the `.devcontainer` image (`./.devcontainer/start.sh`);
  the bare workspace has no toolchains. It ships gcc/g++, protoc, protobuf-c,
  rustup (+ `thumbv7em-none-eabihf`, `riscv32imac-unknown-none-elf`), Go,
  .NET 9, JDK+Maven, Node+tsx, Bun, python, and the bare-metal cross toolchains:
  `gcc-arm-none-eabi` (newlib-nano), `gcc-riscv64-unknown-elf` (picolibc), and
  xpack `riscv-none-elf-gcc` (the only RISC-V bare-metal libstdc++ → `cpp-riscv`).
- `./scripts/bootstrap.sh` pins **`SOFABGEN_VERSION`** and stamps it in
  `tools/.sofabgen-version`. The stamp invalidates BOTH the prebuilt binary and
  all corelib clones — generator and corelibs are released in lockstep; a stale
  corelib can silently produce a wrong wire. After bumping the version, re-run
  bootstrap (the stamp mismatch forces a clean refresh) and document in the
  bootstrap comment block what the new version changes.

## The optimization matrix (identical per row — never diverge)

| category | C/C++ | Rust | managed runtimes |
|---|---|---|---|
| maxspeed | `-O3 -march=native -flto` (`-std=c++20`) | `RUSTFLAGS="-C target-cpu=native"` + `[profile.release] lto=true, codegen-units=1` in **both** crates | tuning env exported once in `bench.sh`, applied to both impls: Go `GOGC=400 GOMAXPROCS=1`; JVM `-XX:+UseParallelGC -Xms512m -Xmx512m -XX:+AlwaysPreTouch`; .NET `DOTNET_gcServer=0 DOTNET_gcConcurrent=0 DOTNET_GCgen0size=0x4000000 DOTNET_TieredPGO=1`; Node/Bun: defaults (V8 heap flags measured, no effect) |
| embedded (host) | `-Os -flto -std=c99` | `opt-level="z", lto=true, codegen-units=1, panic="abort"` | — |
| embedded (bare-metal) | `-Os -flto -DNDEBUG -ffunction-sections -fdata-sections` + ISA flags, link `--specs=nano.specs --specs=nosys.specs -Wl,--gc-sections` | `#![no_std]` staticlib via the `*-ffi` crates, same profile as host embedded, linked by the same C driver/baseline | — |

Timing: the contract says CPU time (`CLOCK_PROCESS_CPUTIME_ID` in C++, language
equivalents elsewhere); the c-embedded targets share `languages/c-embedded/bench.h`
(monotonic clock). Whatever the target uses, it must be **the same helper for
every impl in that target** — that is the fairness requirement.

## Checklists

### Add a new maxspeed language

1. Corelib exists? Add its repo to `CORELIBS` in `scripts/bootstrap.sh` (cloned
   into `vendor/`). Add the language toolchain to `.devcontainer/Dockerfile`.
2. Create `languages/<name>/` with:
   - `meta`: `category=maxspeed` + `metric=throughput`.
   - `sofab/cfg.yaml` + driver; `protobuf/` driver. Generation in `setup.sh`:
     `$SOFABGEN --config sofab/cfg.yaml --lang <l> --in $ROOT/schema/message.sofab.yaml --out sofab/gen`
     and `protoc` (or the runtime's own plugin) for the baseline. sofabgen ≥
     v0.14.0 rejects unknown cfg keys hard — only add honored options.
   - `setup.sh`: **idempotent**, builds both impls with the flags from the
     matrix above — bit-for-bit the same optimization level for both. Corelib
     comes from `vendor/corelib-*` (path dep / include path), baseline from the
     ecosystem's package manager, fetched at build time.
   - `bench.sh`: export `STATE_JSON` + a `BENCH_ITERS` default sized so the
     timed loop runs long enough to be stable; export runtime tuning for BOTH
     impls with a comment justifying each knob; run sofab first, then the
     baseline; print nothing else on stdout.
3. Driver rules (both impls): fill exactly per `schema/STATE.md` (load
   `state.json` outside the timed region, or hardcode); warm-up round-trip +
   re-encode self-check + SHA-256 before timing; exit non-zero on mismatch;
   time only encode+decode; emit the exact `BENCH` line.
4. Register the target in the default `LANGS` list in `scripts/run_benchmark.sh`.
5. Validate: `LANGS="<name>" ./scripts/run_benchmark.sh` — the gate must show
   `434B ok` (sofab) and `494B ok` (baseline). Then a full run; update
   README/RESULTS tables. Commit generated sources.

### Add a new embedded target

Two halves, mirroring the existing pattern:

- **Host target** (`<lang>-embedded`): like a maxspeed target but built with
  the embedded flags (`-Os -flto` / `opt-level=z`), fixed-capacity containers,
  emitting BENCH (+ legacy object-sum FOOTPRINT) lines. Baselines are the
  footprint-oriented libraries (nanopb/EmbeddedProto/micropb), fetched into
  `vendor/` by `setup.sh` (pin a tag), never a desktop runtime (protobuf-c is
  allowed as a labeled reference only).
- **Bare-metal siblings** (`<lang>-cortex-m`, `<lang>-riscv`): footprint-only,
  build-only. `setup.sh` verifies the cross toolchain and reuses the host
  sibling's generated code (calls its setup if missing); `bench.sh` just execs
  `footprint.sh`. `footprint.sh` implements the **link-delta methodology** —
  copy an existing one (`c-cortex-m/footprint.sh` is the reference):
  minimal driver calling the real encode+decode entry points through a
  `volatile` sink, driver state in a custom `.harness` section so it never
  counts toward the codec, an empty-baseline program, both linked with
  `-Wl,--gc-sections`, report per-section `codec − baseline` (clamped ≥ 0) as
  one `FOOTPRINT` line per impl. ISAs: cortex-m4 hard-float
  (`-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16`) and rv32imac.
  Rust codecs enter via `#![no_std]` staticlib FFI crates
  (`rust-embedded/{sofab-ffi,micropb-ffi}`) linked into the **same** C driver.

### Add a new baseline library (new opponent in an existing target)

1. Add a subdir `languages/<target>/<impl>/` with driver + generation in that
   target's `setup.sh`, compiled with the **exact same flags** as the row's
   other impls, and run from `bench.sh`. The runner auto-discovers impls from
   the emitted lines — no registry to edit.
2. The impl name lands in `impl=<name>`; keep it short and lowercase.
3. If it is protobuf-family, its wire must match the 494-byte reference SHA —
   the gate enforces this automatically. A non-protobuf format would need a new
   reference wire in `run_benchmark.sh` (`expected_sha`), `docs/BENCH.md` and
   `schema/STATE.md` — do that consciously, it widens the fairness contract.
4. Mind the license (EmbeddedProto precedent: GPL output stays gitignored,
   fetch build-time only, credit in README).

### Bump sofabgen / corelibs

1. Bump `SOFABGEN_VERSION` in `scripts/bootstrap.sh` and extend the comment
   block with what the release changes; re-run `./scripts/bootstrap.sh` (the
   stamp forces re-download + fresh corelib clones — never bump one without the
   other).
2. If codegen options changed, adjust the `languages/*/sofab/cfg.yaml` files.
3. Full run. If the sofab wire changed size/SHA (as in v0.11.0), update the
   references in `docs/BENCH.md`, `schema/STATE.md`, `scripts/run_benchmark.sh`
   and the README, and explain the change where the old value was documented.
4. Commit regenerated sources; refresh RESULTS.txt + README tables.

## Gotchas

- stdout of `bench.sh` is parsed — keep it to BENCH/FOOTPRINT lines only; all
  logging goes to stderr. Setup noise is fine (captured to a log).
- `typescript-bun` builds nothing: it reruns `languages/typescript`'s generated
  benches under Bun/JSC — one codebase, two JS engines. Keep them in lockstep.
- Bare-metal targets depend on their host sibling's `gen/` output — regenerate
  the host target first (their setup.sh does this automatically).
- Python's 0.10× is analyzed and expected (protobuf-python is a shell over the
  C `upb` engine); see `languages/python/README.md` before "fixing" it. The
  sofab side must run the native accelerator (`sofab.IMPL == "native"`).
- Perf work belongs in the **generator/corelibs**, not in per-target patches —
  all historical `*.patch` hacks were folded upstream (sofabgen v0.6.0+); see
  `docs/perf/bottlenecks.md` for the methodology and what was already tried.
- `.devcontainer/.env` holds a real `GITHUB_TOKEN` (gitignored) — never commit
  or echo it.
- Results tables in README are hand-refreshed from `results/RESULTS.txt` after
  a full `RUNS=5` run on the reference host — don't edit numbers ad hoc.
