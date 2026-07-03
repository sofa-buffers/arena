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
into two side-by-side tables.

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
| **Embedded** — cpp-cortex-m | `corelib-c-cpp` C++ wrapper, **bare-metal cross-build** | **EmbeddedProto** | footprint |
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

> **Reading footprint (`.text`/RAM).** Two methodologies, reported separately:
> - **Host object-sum** (`c-embedded`, `cpp-embedded`): each library's own compiled
>   code (`-Os`, **no libc**, x86-64) section-summed with `size`. Counts the **whole
>   library**, so it over-counts a generic runtime that `--gc-sections` would trim
>   in real firmware.
> - **Bare-metal link delta** (`c-cortex-m`, `cpp-cortex-m`, `rust-cortex-m`,
>   `c-riscv`, `rust-riscv`) — the **fair, firmware-representative** metric: each
>   codec is cross-compiled (`-Os -DNDEBUG`; Rust: `#![no_std]` staticlib,
>   `opt-level=z` + LTO) and linked into a minimal program with
>   `-Wl,--gc-sections`; the figure is *codec program − empty baseline* — exactly
>   the flash/RAM the codec adds to an application, including libc routines only
>   it pulls in. These targets are **build-only** (never executed), so they emit
>   no `BENCH` line.
>
> The host `rust-embedded` row reports wire + throughput only: a host object-sum
> for Rust is dominated by std, not codec — its footprint lives in the bare-metal
> `rust-cortex-m` / `rust-riscv` rows (real generated `no_std` code since
> sofabgen 0.9.0 closed generator issue #40).

## Quick start

The [`.devcontainer`](.devcontainer) ships the full multi-language toolchain —
`./.devcontainer/start.sh` builds and drops you into the image, including the
bare-metal cross toolchains (`gcc-arm-none-eabi` + newlib/libstdc++ and
`gcc-riscv64-unknown-elf` + picolibc) used by the footprint-only targets. Embedded
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
byte-identity gate, and prints — and writes to `results/RESULTS.txt` — the two
tables below.

<!-- RESULTS:BEGIN -->
## Results

Every target passes the byte-identity gate: all SofaBuffers targets emit the same
**436-byte** wire (the C object API is **434 B** — see note), and every
protobuf-family baseline emits the same **494-byte** wire.

### Maxspeed — throughput

| language | sofab size | proto size | sofab MB/s | proto MB/s | **size** adv | **speed** adv |
|---|--:|--:|--:|--:|:--:|:--:|
| C++        | 436 | 494 | 335.5 | 233.5 | **1.13×** | **1.44×** |
| Rust       | 436 | 494 | 347.8 | 245.6 | **1.13×** | **1.42×** |
| Go         | 436 | 494 | 136.8 | 137.8 | **1.13×** | 0.99× |
| C#         | 436 | 494 | 119.6 | 133.9 | **1.13×** | 0.89× |
| Java       | 436 | 494 | 234.8 | 275.2 | **1.13×** | 0.85× |
| TypeScript | 436 | 494 |  49.9 |  62.1 | **1.13×** | 0.80× |
| Python     | 436 | 494 |  20.9 | 192.6 | **1.13×** | 0.11× |

*size adv = protobuf_bytes / sofab_bytes (>1 → SofaBuffers smaller). speed adv =
sofab_MBps / protobuf_MBps (>1 → SofaBuffers faster). Throughput is **best-of-5**
(`RUNS=5`; noise is downward), machine-dependent, and comparable **only within a
row**. Compiled targets build `-O3 -march=native -flto` (adaptive, rebuilt per
host); VM targets use portable GC/JIT tuning — identical for both impls in a row.*

### Embedded — code footprint (isolated codec, `-Os`, no libc; **lower is better**)

| target | impl | wire | `.text` | `.rodata` | static-RAM | `.text` vs sofab |
|---|---|--:|--:|--:|--:|:--:|
| **c-embedded** | sofab | 434 | **5 918** | 1 382 | 192 | 1.00× |
| | nanopb | 494 | 9 621 | 1 057 | 248 | 1.63× |
| | protobuf-c | 494 | 26 267 | 4 015 | 2 632 | 4.44× |
| **cpp-embedded** | sofab | 436 | 10 151 | 1 572 | 712 | 1.00× |
| | **embeddedproto** | 494 | **3 276** | 261 | 352 | **0.32×** |
| **rust-embedded** | sofab | 436 | — | — | — | *(see rust-cortex-m / rust-riscv)* |
| | micropb | 494 | — | — | — | |

*Footprint is the host object-sum (whole library, no libc). `.text vs sofab` >1
means the baseline carries more code than SofaBuffers. Rust footprint is only
reported bare-metal — a host object-sum for Rust is std-dominated, not codec.*

### Embedded — bare-metal footprint (`--gc-sections` link delta; **lower is better**)

What the codec **actually adds to firmware**: cross-compiled `-Os -DNDEBUG`, linked
into a minimal program with `-Wl,--gc-sections`, reported as *codec program − empty
baseline*. Build-only targets — the binaries are never executed.

| target (ISA) | impl | `.text` | `.rodata` | static-RAM | `.text` vs sofab |
|---|---|--:|--:|--:|:--:|
| **c-cortex-m** (thumbv7e-m+fp) | sofab | **3 360** | 344 | 0 | 1.00× |
| | nanopb | 5 860 | 933 | 0 | 1.74× |
| **cpp-cortex-m** (thumbv7e-m+fp) | sofab | **6 784** | 180 | 132 | 1.00× |
| | embeddedproto | 8 568 | 908 | 364 | 1.26× |
| **rust-cortex-m** (thumbv7e-m+fp) | sofab | **5 720** | 328 | 0 | 1.00× |
| | micropb | 8 236 | 261 | 0 | 1.44× |
| **c-riscv** (rv32imac) | sofab | **3 528** | 488 | 0 | 1.00× |
| | nanopb | 6 488 | 1 112 | 0 | 1.84× |
| **rust-riscv** (rv32imac) | sofab | **6 232** | 392 | 0 | 1.00× |
| | micropb | 9 680 | 393 | 0 | 1.55× |

*Rust rows are the real sofabgen-generated `#![no_std]` code (heapless
containers, sofabgen ≥ 0.9.0) vs micropb — both heap-free staticlibs
(`opt-level=z`, LTO, `panic=abort`) linked through the same C driver/baseline.
C++ on RISC-V: not measurable with the packaged toolchain — Ubuntu's
`riscv64-unknown-elf` ships picolibc but no bare-metal libstdc++.*

### The big picture

- **On the wire, SofaBuffers wins everywhere — consistently ~13% smaller** (494 →
  436 B; the C object API is leaner still at 434 B). Same message, every language.
- **Maxspeed: after tuning the generated code, three languages beat or tie protobuf
  and the rest are close.** The deficit was never the wire format — it was the
  generated per-message code and its data model *above* the byte codec. Those fixes
  now ship natively in **sofabgen v0.6.0** (full analysis:
  [`docs/perf/bottlenecks.md`](docs/perf/bottlenecks.md)).
  - **C++ 1.44× and Rust 1.42× — SofaBuffers *beats* protobuf.** Lean wire + fixed
    stack arrays + a direct switch-into-fields decode, vectorized under
    `-O3 -march=native -flto` / `target-cpu=native` + LTO.
  - **Go: ~parity (0.99×)** (was 0.40×): decode via the corelib's zero-copy cursor
    instead of a byte-at-a-time reader, plus a byte-slice encoder.
  - **C# 0.89×, Java 0.85×, TypeScript 0.80× — close** (were 0.79× / 0.65× / 0.66×):
    primitive fixed arrays instead of boxed/heap collections, single-shot string
    decode, and for TS a monomorphic decoder + allocation-free UTF-8 encode. The
    residual gap tracks per-VM runtime maturity, not the format.
  - **Python: 0.11× — the outlier.** protobuf-python is a thin shell over Google's C
    **`upb`** engine, while SofaBuffers keeps a per-field Python driver (it *does* run
    the native Cython accelerator, not a fallback). Full profile:
    [`languages/python/README.md`](languages/python/README.md).
- **Embedded, on the metric that matters — bare-metal link delta — SofaBuffers wins
  every row, in all three languages.** On a Cortex-M4 the C codec adds **3.4 KB**
  of flash where nanopb adds 5.9 KB (**1.74×**); on rv32imac it's **3.5 KB** vs
  6.5 KB (**1.84×**); the C++ wrapper adds **6.8 KB** where EmbeddedProto adds
  8.6 KB (**1.26×**) — with less static RAM (132 B vs 364 B); and the Rust
  `no_std` codec adds **5.7 KB** where micropb adds 8.2 KB on Cortex-M4
  (**1.44×**), **6.2 KB** vs 9.7 KB on rv32imac (**1.55×**). All drivers heap-free.
  - The host **object-sum** tells a different story for C++ (EmbeddedProto's counted
    sources are just 3.3 KB) — because it counts *compilation units*, not what the
    linker actually keeps. Once both codecs are linked into firmware with
    `--gc-sections` and asserts stripped (`-DNDEBUG`), the templates EmbeddedProto
    instantiates across the message tree outweigh SofaBuffers' shared C core. Both
    numbers are reported; the link delta is the firmware-representative one.
  - **C:** the SofaBuffers object API is the smallest codec on **every** metric —
    host object-sum (5.9 KB vs 9.6 KB nanopb / 26.3 KB `protobuf-c`) and both
    bare-metal ISAs.
  - **Rust:** since sofabgen 0.9.0 (closing generator issue #40) the generated
    crate is genuinely `#![no_std]` and heap-free (heapless containers) under
    `--no-default-features` — so the bare-metal rows measure the **real generated
    code**, not a synthetic harness. The host `rust-embedded` row still carries
    wire + throughput (436 B, sofab faster than micropb there too).

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
                   delta on the cross targets (c-/cpp-/rust-cortex-m, c-/rust-riscv)
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
