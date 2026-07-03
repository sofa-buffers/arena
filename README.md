<p align="center"><img src="assets/sofabuffers_logo.png" alt="SofaBuffers" height="140"></p>

# SofaBuffers vs. The World

<b>Structured Objects For Anyone</b><br>
<i>... so optimized, feels amazing.</i>

## Overview

This is a **multi-language benchmark arena**: it builds **SofaBuffers** and a
serialization baseline against one identical message and measures who is leanest
and fastest — split into **two categories** so we compare like with like instead
of mixing goals:

> - **Maxspeed** — for the **same message**, how fast does **SofaBuffers**
>   encode+decode vs Google's **Protocol Buffers**, in **C++, Rust, Go, C#, Java,
>   TypeScript and Python**? Ranked by **throughput (MB/s)**.
> - **Embedded** — how small is the **SofaBuffers** codec (**`.text` / RAM**) vs
>   **footprint-oriented** protobuf libraries — **nanopb, micropb, EmbeddedProto**
>   (and `protobuf-c` for reference) — in **C, C++ and Rust**? Ranked by **code size**.

The point of the split: a throughput-tuned corelib is measured against a
throughput-tuned protobuf runtime, and an *embedded* corelib against an *embedded*
protobuf library. Same message, same values, everywhere. One runner collects it all
into the result tables below.

## The message (identical everywhere)

One message definition, expressed twice — once for each generator:

- SofaBuffers: [`schema/message.sofab.yaml`](schema/message.sofab.yaml) → compiled by
  [`sofabgen`](https://github.com/sofa-buffers/generator) to typed code against each
  language's [corelib](https://github.com/sofa-buffers).
- Protobuf: [`schema/message.proto`](schema/message.proto) → compiled by `protoc`
  (or each library's own plugin) to typed code against its runtime.

It is a deliberately "full scale" message — every scalar width, floats, strings,
raw bytes, eight numeric arrays, a nested struct, an array-of-structs, and an
array of Unicode strings. The single source of truth for the field **values**
every target fills is [`schema/STATE.md`](schema/STATE.md)
(machine form: [`schema/state.json`](schema/state.json)).

## The two categories

| | SofaBuffers corelib | baseline(s) | ranked by |
|---|---|---|---|
| **Maxspeed** — cpp, rust | `corelib-cpp` (C++20), `corelib-rs` (std) | Google protobuf (`libprotobuf`, prost) | throughput |
| **Maxspeed** — go, csharp, java, typescript, python | each language's corelib | Google protobuf runtime | throughput |
| **Embedded** — c-embedded | `corelib-c-cpp` (C object API) | **nanopb** + `protobuf-c` (ref) | footprint |
| **Embedded** — cpp-embedded | `corelib-c-cpp` C++ wrapper (`corelib: c-cpp`) | **EmbeddedProto** | footprint |
| **Embedded** — rust-embedded | `corelib-rs-no-std` (no_std, no-alloc) | **micropb** | footprint |
| **Embedded** — c-cortex-m, c-riscv | `corelib-c-cpp` (C object API), **bare-metal cross-build** | **nanopb** | footprint |
| **Embedded** — cpp-cortex-m, cpp-riscv | `corelib-c-cpp` C++ wrapper, **bare-metal cross-build** | **EmbeddedProto** | footprint |
| **Embedded** — rust-cortex-m, rust-riscv | `corelib-rs-no-std` (no_std codegen, sofabgen ≥ 0.9.0), **bare-metal cross-build** | **micropb** | footprint |

## How the comparison is kept fair

Every target obeys one [benchmark contract](docs/BENCH.md). Each emits one or both
uniform, machine-readable lines:

```
BENCH     lang=<l> impl=<i> serialized_bytes=<n> iters=<n> cpu_time_s=<f> throughput_mbs=<f> sha256=<hex>
FOOTPRINT lang=<l> impl=<i> text=<n> rodata=<n> data=<n> bss=<n>
```

- **Same message, same values.** All fields identical across every target.
- **Warm-up + self-check outside the timed loop.** One round-trip up front captures
  the wire size and SHA-256 and asserts the decoded message re-encodes to identical
  bytes; a target that fails exits non-zero.
- **Only encode + decode is timed.** Construction, JSON parsing and I/O are not
  counted. Within a target, SofaBuffers and its baseline use the **identical timing
  method and iteration count**.
- **A byte-identity gate.** Every `sofab` target emits the same wire, and *every*
  protobuf-family baseline (`protobuf`, `protobuf-c`, `nanopb`, `micropb`,
  `embeddedproto`) emits the identical **494-byte** protobuf wire. A drifted fill in
  any language is caught automatically.
- **Optimized per category, portably, identically per row.** Maxspeed targets build
  for speed — `-O3 -march=native -flto` (C/C++), `target-cpu=native` + LTO (Rust),
  and portable runtime tuning for the VMs (workstation/server GC, `GOGC`, ParallelGC,
  TieredPGO). Embedded targets build for size — `-Os -flto`. Nothing pins a CPU/ISA
  level: `-march=native` is *adaptive* and the arena rebuilds on each host, so it runs
  anywhere; and within a row SofaBuffers and its baseline get the **same** flags.
  Throughput is reported **best-of-5** (`RUNS=5`, the default) since it is noisy.

> **Reading throughput (`MB/s`).** An encode+decode figure on **this host**, only
> meaningful **within a language** (each runs on a different runtime — JIT, VM,
> interpreter, native). It is machine-dependent and varies run-to-run. The columns
> comparable *across* rows are **wire size** and the **per-target ratios**.

> **Reading footprint (`.text`/RAM).** The reported metric is the **bare-metal
> link delta** (`c-cortex-m`, `cpp-cortex-m`, `rust-cortex-m`, `c-riscv`,
> `cpp-riscv`, `rust-riscv`) — fair and firmware-representative: each codec is
> cross-compiled (`-Os -flto -DNDEBUG`; Rust: `#![no_std]` staticlib,
> `opt-level=z` + LTO) and linked into a minimal program with
> `-Wl,--gc-sections`; the figure is *codec program − empty baseline* — exactly
> the flash/RAM the codec adds to an application, including libc routines only
> it pulls in. These targets are **build-only** (never executed), so they emit
> no `BENCH` line.
>
> The host embedded targets still emit their `FOOTPRINT` lines (an x86-64
> object-sum; raw data under `results/raw/`), but that metric is no longer
> tabulated: it counts each library's *whole* compiled code, over-counting
> generic runtimes that `--gc-sections` would trim in real firmware — the link
> delta supersedes it. The host `rust-embedded` target reports wire +
> throughput only (a host object-sum for Rust is std-dominated, not codec);
> Rust footprint lives in the bare-metal rows (real generated `no_std` code
> since sofabgen 0.9.0 closed generator issue #40).

## Quick start

The [`.devcontainer`](.devcontainer) ships the full multi-language toolchain —
`./.devcontainer/start.sh` builds and drops you into the image, including the
bare-metal cross toolchains (`gcc-arm-none-eabi` + newlib/libstdc++,
`gcc-riscv64-unknown-elf` + picolibc, and the xpack `riscv-none-elf` GCC — the
only one with a RISC-V bare-metal libstdc++, for `cpp-riscv`) used by the
footprint-only targets. Embedded
baselines also need `protoc` and a network fetch of nanopb / EmbeddedProto
(build-time only).

```bash
# one-time: fetch sofabgen + the corelibs + the python protobuf toolchain
./scripts/bootstrap.sh

# build every target, run them, print both tables (best-of-5 throughput by default)
./scripts/run_benchmark.sh

# handy variants
LANGS="cpp rust c-embedded" ./scripts/run_benchmark.sh     # a subset (any category)
BENCH_ITERS=100000 ./scripts/run_benchmark.sh     # fewer iterations
RUNS=1 ./scripts/run_benchmark.sh                 # single quick run (skip best-of-5)
./scripts/run_benchmark.sh --no-setup             # reuse existing builds
```

`run_benchmark.sh` is the single entry point: per target it runs
`languages/<name>/setup.sh` then `bench.sh`, reads its category from
`languages/<name>/meta`, parses every `BENCH`/`FOOTPRINT` line, enforces the
byte-identity gate, and prints — and writes to `results/RESULTS.txt` — the
tables below.

<!-- RESULTS:BEGIN -->
## Results

Every target passes the byte-identity gate: all SofaBuffers targets emit the same
**436-byte** wire (the C object API is **434 B** — see note), and every
protobuf-family baseline emits the same **494-byte** wire.

### Maxspeed — throughput

| language | sofab size | proto size | sofab MB/s | proto MB/s | **size** adv | **speed** adv |
|---|--:|--:|--:|--:|:--:|:--:|
| C++        | 436 | 494 | 335.5 | 234.4 | **1.13×** | **1.43×** |
| Rust       | 436 | 494 | 350.3 | 246.6 | **1.13×** | **1.42×** |
| Go         | 436 | 494 | 140.6 | 139.0 | **1.13×** | **1.01×** |
| C#         | 436 | 494 | 120.7 | 132.8 | **1.13×** | 0.91× |
| Java       | 436 | 494 | 235.4 | 272.8 | **1.13×** | 0.86× |
| TypeScript | 436 | 494 |  49.4 |  61.3 | **1.13×** | 0.80× |
| Python     | 436 | 494 |  20.7 | 180.5 | **1.13×** | 0.11× |

***C++, Rust and Go beat or tie protobuf; the wire is ~13 % smaller everywhere.**
adv >1 → SofaBuffers ahead; best-of-5, comparable only within a row.*

### Embedded — throughput (host build of the embedded codecs)

Same message, same values, same timing method, **same columns** as maxspeed —
but these are the **embedded-friendly** implementations (fixed-capacity
containers, built `-Os`), so speed is an interesting factor here, **not the
ranking metric** (that is footprint, below).

| target | sofab size | proto size | sofab MB/s | proto MB/s | **size** adv | **speed** adv |
|---|--:|--:|--:|--:|:--:|:--:|
| c-embedded vs protobuf-c    | 434 | 494 | 123.0 | 296.7 | **1.14×** | 0.41× |
| c-embedded vs nanopb        | 434 | 494 | 123.0 |  59.7 | **1.14×** | **2.06×** |
| rust-embedded vs micropb    | 436 | 494 | 140.4 | 125.1 | **1.13×** | **1.12×** |
| cpp-embedded vs embeddedproto | 436 | 494 | 131.7 |  63.1 | **1.13×** | **2.09×** |

***Even built for size, the SofaBuffers codecs outrun every embedded protobuf
baseline** (~2× vs nanopb and EmbeddedProto) — only the desktop-class
`protobuf-c` is faster.*

### Embedded — bare-metal footprint (`--gc-sections` link delta; **lower is better**)

What the codec **actually adds to firmware**: cross-compiled `-Os -flto -DNDEBUG`
(Rust: `#![no_std]` staticlib, `opt-level=z` + LTO), linked into a minimal program
with `-Wl,--gc-sections`, reported as *codec program − empty baseline*. Build-only
targets — the binaries are never executed.

| target (ISA) | impl | `.text` | `.rodata` | static-RAM | `.text` vs sofab |
|---|---|--:|--:|--:|:--:|
| **c-cortex-m** (thumbv7e-m+fp) | sofab | **3 060** | 344 | 0 | 1.00× |
| | nanopb | 5 660 | 936 | 0 | 1.85× |
| **cpp-cortex-m** (thumbv7e-m+fp) | sofab | **6 484** | 156 | 132 | 1.00× |
| | embeddedproto | 8 412 | 908 | 364 | 1.30× |
| **rust-cortex-m** (thumbv7e-m+fp) | sofab | **5 720** | 328 | 0 | 1.00× |
| | micropb | 8 236 | 261 | 0 | 1.44× |
| **c-riscv** (rv32imac) | sofab | **3 128** | 488 | 0 | 1.00× |
| | nanopb | 6 336 | 1 112 | 0 | 2.03× |
| **cpp-riscv** (rv32imac) | sofab | **5 944** | 300 | 420 | 1.00× |
| | embeddedproto | 8 898 | 1 012 | 652 | 1.50× |
| **rust-riscv** (rv32imac) | sofab | **6 232** | 392 | 0 | 1.00× |
| | micropb | 9 680 | 393 | 0 | 1.55× |

***SofaBuffers wins all six rows — three languages × two ISAs** (1.30×–2.03×
less flash than the smallest protobuf alternative).*

### The big picture

- **On the wire, SofaBuffers wins everywhere — consistently ~13% smaller** (494 →
  436 B; the C object API is leaner still at 434 B). Same message, every language.
- **Maxspeed: after tuning the generated code, three languages beat or tie protobuf
  and the rest are close.** The deficit was never the wire format — it was the
  generated per-message code and its data model *above* the byte codec. Those fixes
  now ship natively in **sofabgen v0.6.0** (full analysis:
  [`docs/perf/bottlenecks.md`](docs/perf/bottlenecks.md)).
  - **C++ 1.43× and Rust 1.42× — SofaBuffers *beats* protobuf.** Lean wire + fixed
    stack arrays + a direct switch-into-fields decode, vectorized under
    `-O3 -march=native -flto` / `target-cpu=native` + LTO.
  - **Go: ~parity (1.01×)** (was 0.40×): decode via the corelib's zero-copy cursor
    instead of a byte-at-a-time reader, plus a byte-slice encoder.
  - **C# 0.91×, Java 0.86×, TypeScript 0.80× — close** (were 0.79× / 0.65× / 0.66×):
    primitive fixed arrays instead of boxed/heap collections, single-shot string
    decode, and for TS a monomorphic decoder + allocation-free UTF-8 encode. The
    residual gap tracks per-VM runtime maturity, not the format.
  - **Python: 0.11× — the outlier.** protobuf-python is a thin shell over Google's C
    **`upb`** engine, while SofaBuffers keeps a per-field Python driver (it *does* run
    the native Cython accelerator, not a fallback). Full profile:
    [`languages/python/README.md`](languages/python/README.md).
- **Embedded, on the metric that matters — bare-metal link delta — SofaBuffers wins
  all six rows: three languages × two ISAs.** C: **3.1 KB** vs nanopb 5.7 KB on
  Cortex-M4 (**1.85×**), **3.1 KB** vs 6.3 KB on rv32imac (**2.03×**). C++:
  **6.5 KB** vs EmbeddedProto 8.4 KB on Cortex-M4 (**1.30×**, with less static
  RAM: 132 B vs 364 B), **5.9 KB** vs 8.9 KB on rv32imac (**1.50×**). Rust
  `no_std`: **5.7 KB** vs micropb 8.2 KB on Cortex-M4 (**1.44×**), **6.2 KB** vs
  9.7 KB on rv32imac (**1.55×**). All drivers heap-free.
  - Beware the naive host **object-sum** (an earlier interim metric): it counts
    *compilation units*, not what the linker keeps, and told the opposite story
    for C++ (EmbeddedProto's counted sources are just 3.3 KB). Linked into
    firmware with `--gc-sections`, LTO and `-DNDEBUG`, the templates
    EmbeddedProto instantiates across the message tree outweigh SofaBuffers'
    shared C core — the link delta is the firmware-representative number and
    the only footprint metric tabulated.
  - **Rust:** since sofabgen 0.9.0 (closing generator issue #40) the generated
    crate is genuinely `#![no_std]` and heap-free (heapless containers) under
    `--no-default-features` — so the bare-metal rows measure the **real generated
    code**, not a synthetic harness. Both Rust impls are heap-free staticlibs
    (`opt-level=z`, LTO, `panic=abort`) linked through the same C driver/baseline.
  - **Toolchains, kept fair:** ARM rows use `gcc-arm-none-eabi` (newlib-nano),
    RISC-V C/Rust rows the apt `riscv64-unknown-elf` (picolibc), and `cpp-riscv`
    the xpack `riscv-none-elf` GCC — the only RISC-V toolchain with a bare-metal
    libstdc++. Each target's delta is measured against a baseline linked with its
    **own** toolchain/libc, so CRT and libc differences cancel per target.
  - **And they're fast anyway:** on the host the embedded SofaBuffers codecs
    outrun nanopb and EmbeddedProto ~2× and beat micropb (1.12×) — despite being built
    for size. Only `protobuf-c` is faster — a desktop library with a heap
    requirement and several times the codec code, unfit for bare metal.

> **Note — why C is 434 B.** The C target is the SofaBuffers *object API*
> (`corelib-c-cpp`), a runtime-descriptor codec for constrained/embedded use. It
> omits the single empty string in `string_array` (a deliberate leanness
> optimization), so its wire is 2 bytes smaller. It is a *correct, expected* variant,
> and the gate checks C against 434 B specifically. (The C++ wrapper of the same
> corelib encodes all five strings, so `cpp-embedded` is 436 B.)

> **Note — why Python is slowest (0.11×), and it's *not* a fallback.** Python trails
> because protobuf-python is a thin shell over Google's C **`upb`** engine while
> SofaBuffers keeps a **per-field Python driver** — it runs the native Cython
> accelerator (`sofab.IMPL == "native"`), not a fallback. See
> [`languages/python/README.md`](languages/python/README.md) for the full profile
> (runtime verification + callgrind attribution table).
<!-- RESULTS:END -->

## Repository layout

```
schema/            the message: message.sofab.yaml, message.proto, STATE.md, state.json
docs/BENCH.md      the uniform benchmark contract every target obeys
languages/
  <name>/
    meta           category=maxspeed|embedded  +  metric=throughput|footprint
    setup.sh       generate + build every impl for this target (idempotent)
    bench.sh       run the impls; print BENCH (+ FOOTPRINT for embedded) lines
    sofab/         SofaBuffers driver + generated code
    protobuf/ | nanopb/ | micropb/ | embeddedproto/   the baseline driver(s)
    footprint.sh   (embedded) object-sum — or bare-metal --gc-sections link
                   delta on the cross targets (c-/cpp-/rust-cortex-m and -riscv)
  common/          shared SHA-256 helper for the C/C++ targets
scripts/
  bootstrap.sh     fetch sofabgen + corelibs + python protobuf venv
  run_benchmark.sh build + run everything, enforce the gate, print both tables
.devcontainer/     the multi-language dev image (Dockerfile + build/start/attach)
tools/             sofabgen + python venv (bootstrapped, gitignored)
vendor/            SofaBuffers corelibs + fetched baselines (nanopb, protobuf-c
                   source, EmbeddedProto) — all cloned, gitignored
```

## Credits

- **SofaBuffers** — the format, generator and corelibs: https://github.com/sofa-buffers
- **Protocol Buffers** — https://protobuf.dev
- Embedded protobuf baselines: **nanopb** (zlib), **micropb** (MIT/Apache-2.0),
  **protobuf-c** (BSD), and **EmbeddedProto** (GPLv3 — used build-time only, fetched
  into gitignored `vendor/`, never redistributed): https://github.com/Embedded-AMS/EmbeddedProto
