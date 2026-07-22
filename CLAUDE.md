# CLAUDE.md — agent entry point

This repo is the **SofaBuffers benchmark arena**: one identical message +
payload, SofaBuffers vs protobuf-family baselines, split into a **maxspeed**
league (throughput) and an **embedded** league (code footprint) so opponents
always play in the same league.

**Do not rely on this file for the details — read the sources of truth:**

| read | for |
|---|---|
| [`README.md`](README.md) | the authoritative overview: the two categories and their opponents, the message, how fairness is kept (flags, gate, best-of-5), quick start, runner usage, repo layout, current results |
| [`docs/BENCH.md`](docs/BENCH.md) | the benchmark contract every target obeys: `BENCH`/`FOOTPRINT` line format, timing rules, self-check, reference wires |
| [`schema/STATE.md`](schema/STATE.md) / [`schema/state.json`](schema/state.json) | the canonical field values every target must fill |
| [`scripts/run_benchmark.sh`](scripts/run_benchmark.sh) header + [`scripts/bootstrap.sh`](scripts/bootstrap.sh) comments | runner semantics; how sofabgen/corelib versions are resolved (bleeding edge, not pinned) |
| [`docs/perf/bottlenecks.md`](docs/perf/bottlenecks.md) | perf methodology + what was already tried (before optimizing anything) |
| `languages/<target>/{meta,setup.sh,bench.sh,footprint.sh}` | the per-target ground truth for flags, tuning and generation |

Everything below is only what is **not** written in those files.

## Invariants with multiple sync points

- **Reference wires** (currently sofab 434 B, protobuf 494 B): sizes + SHA-256s
  are duplicated in `docs/BENCH.md`, `schema/STATE.md`,
  `REF_SOFAB_SHA`/`REF_PROTO_SHA` in `scripts/run_benchmark.sh`, and the README
  prose. Any change to schema, values or generator that moves the wire must
  update **all four** together.
- **`schema/message.sofab.yaml` ↔ `schema/message.proto` mapping rules** (only
  documented in the yaml's header comment): proto field numbers 1..8 ↔ sofab
  ids 0..7 (−1 offset on scalars/struct members); container fields keep their
  number (`nested`=10, `arrays`=100, `string_array`=200); proto `repeated` ↔
  sofab fixed `count: 5`; u8/u16→`uint32`, i8/i16→`int32` (proto has no narrow
  ints); sofab strings carry `maxlen` for fixed-capacity embedded storage.
- **Identical optimization per row** is the fairness core: whatever flag or
  runtime knob one impl gets, every impl in that target gets. The flags live in
  each target's `setup.sh` (compilers, `RUSTFLAGS`, Cargo `[profile.release]` —
  in **both** crates) and `bench.sh` (VM tuning env, exported once for both
  impls, each knob justified in a comment). Tuning must stay portable — never
  pin a CPU/ISA level.
- The runner has **no impl registry**: impls appear by emitting
  `BENCH`/`FOOTPRINT` lines, which is why `bench.sh` stdout must contain
  nothing else (logs → stderr).
- **Generated-manifest version pins**: the committed `sofab/gen/` manifests and
  `go/protobuf/go.mod` are *generated* by `setup.sh`, so `languages/versions.sh`
  (sourced by each `setup.sh`) is their single source of truth and
  `.github/renovate.json` lists them under `ignorePaths` — Renovate must never
  bump a generated file (the next `setup.sh` run reverts it = the drift this
  removes). Deps shared with a hand-written protobuf/micropb manifest are a sync
  point: bump `versions.sh` **and** the paired manifest together (listed in the
  `versions.sh` header); Renovate still maintains the hand-written side.

## Checklists

### Add a new maxspeed language

1. Add the corelib repo to `CORELIBS` in `scripts/bootstrap.sh` (cloned into
   `vendor/`); add the toolchain to `.devcontainer/Dockerfile`.
2. Create `languages/<name>/` mirroring an existing target (e.g. `rust/`):
   `meta` (`category=maxspeed`, `metric=throughput`), `sofab/cfg.yaml` + driver,
   `protobuf/` driver, idempotent `setup.sh` (sofabgen + protoc generation,
   identical flags for both impls), `bench.sh` (export `STATE_JSON`, a
   `BENCH_ITERS` default large enough for a stable loop, tuning env for both
   impls; run sofab first). sofabgen ≥ v0.14.0 rejects unknown cfg keys hard.
3. Drivers follow `docs/BENCH.md`: fill per `schema/STATE.md` (load
   `state.json` outside the timed region, or hardcode), warm-up round-trip +
   re-encode self-check before timing, exit non-zero on mismatch.
4. Add the target to the default `LANGS` list in `scripts/run_benchmark.sh`.
5. Validate: `LANGS="<name>" ./scripts/run_benchmark.sh` — gate must show
   `434B ok` / `494B ok`. Commit generated sources (README explains what is
   committed vs gitignored; GPL EmbeddedProto output never).

### Add a new embedded target

- **Host half** (`<lang>-embedded`): like a maxspeed target but embedded flags
  (`-Os -flto` / `opt-level=z,lto,codegen-units=1,panic=abort`), fixed-capacity
  containers, footprint-oriented baselines only (nanopb/EmbeddedProto/micropb;
  pin a tag when fetching into `vendor/`), emits BENCH lines.
- **Bare-metal siblings** (`<lang>-cortex-m`, `<lang>-riscv`): footprint-only,
  build-only, never executed. `setup.sh` verifies the cross toolchain and
  reuses the host sibling's `gen/` (calls its setup if missing); `bench.sh`
  just execs `footprint.sh`. Copy the link-delta methodology from
  `languages/c-cortex-m/footprint.sh` (the reference): minimal driver calling
  the real encode+decode through a `volatile` sink, driver state in a custom
  `.harness` section so it never counts toward the codec, an empty-baseline
  program, `-Wl,--gc-sections`, emit per-section `codec − baseline` (clamped
  ≥ 0). Rust codecs enter as `#![no_std]` staticlibs via the
  `rust-embedded/{sofab-ffi,micropb-ffi}` crates, linked into the **same** C
  driver as the C targets.

### Add a new baseline library (new opponent)

1. New subdir `languages/<target>/<impl>/` + generation in that target's
   `setup.sh` with the **exact same flags** as the row's other impls + a run in
   `bench.sh`. Nothing to register — the runner discovers impls from output.
2. Protobuf-family baselines must match the 494 B reference wire (gate enforces
   it). A non-protobuf format needs a new reference wire in
   `run_benchmark.sh` (`expected_sha`), `docs/BENCH.md` and `schema/STATE.md` —
   a conscious widening of the fairness contract.
3. Mind the license (EmbeddedProto precedent: GPL output gitignored, fetched
   build-time only, credited in README).

### Bump sofabgen / corelibs

1. Nothing to bump — `scripts/bootstrap.sh` pins neither side: corelibs are
   reset to their remote `main` HEAD and sofabgen is fetched from the
   generator's *newest successful CI build on main* (the per-commit
   `sofabgen-<os>-<arch>` workflow **artifact**, not a tagged release) via the
   GitHub Actions API on every run. Just re-run bootstrap; the
   `tools/.sofabgen-version` stamp (now the resolved workflow **run id**) forces
   a fresh binary when the tip advances (a stale corelib can silently produce a
   wrong wire). The artifacts API is auth-only, so a `GITHUB_TOKEN` in
   `.devcontainer/.env` is now **required**. For a reproducible run, pin per
   invocation with `SOFABGEN_RUN_ID=<run-id> ./scripts/bootstrap.sh`.
2. Adjust `languages/*/sofab/cfg.yaml` if codegen options changed; full run;
   if the wire moved, update all four reference sync points; commit
   regenerated sources; refresh `results/RESULTS.txt` + README tables.

### Change the message or payload

Touch **together**: both schema files (keep the mapping rules above),
`state.json` + `STATE.md`, every hardcoded fill (C/C++ benches, bare-metal
footprint drivers, nanopb `message.options`), then re-run everything and update
the four reference-wire sync points. This friction is deliberate — the
reference wires are the fairness anchor.

## Gotchas

- `typescript-bun` builds nothing: it reruns `languages/typescript`'s generated
  benches under Bun/JSC — keep the two targets in lockstep.
- Timing helper may differ per target (C++ uses CPU-time clock, the c-embedded
  family shares `languages/c-embedded/bench.h`) — what matters is that every
  impl in a target uses the **same** helper.
- Perf work belongs in the generator/corelibs, not per-target patches — all
  historical `*.patch` hacks were folded upstream (sofabgen ≥ v0.6.0); read
  `docs/perf/bottlenecks.md` first. Python's 0.10× is analyzed and expected
  (`languages/python/README.md`).
- README result tables are hand-refreshed from `results/RESULTS.txt` after a
  full `RUNS=5` run — never edit numbers ad hoc.
- `.devcontainer/.env` holds a real `GITHUB_TOKEN` (gitignored) — never commit
  or echo it. Work inside the devcontainer; the bare workspace has no
  toolchains.
