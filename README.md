<p align="center"><img src="assets/sofabuffers_logo.png" alt="SofaBuffers" height="140"></p>

# SofaBuffers vs. The World

<b>Structured Objects For Anyone</b><br>
<i>... so optimized, feels amazing.</i>

## Arena

This is a **multi-language benchmark arena**: it builds **SofaBuffers** and a
serialization baseline against one identical message and measures who is leanest
and fastest — split into **two categories** so we compare like with like instead
of mixing goals:

> - **Maxspeed** — for the **same message**, how fast does **SofaBuffers**
>   encode+decode vs **Protocol Buffers**, in **C++, Rust, Zig, Go, C#, Java,
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
| **Maxspeed** — zig | `corelib-zig` | [zig-protobuf](https://github.com/Arwalk/zig-protobuf) (Arwalk) | throughput |
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

> **Reading throughput (`MB/s` and `msg/s`).** An encode+decode figure on **this
> host**, only meaningful **within a language** (each runs on a different runtime —
> JIT, VM, interpreter, native). It is machine-dependent and varies run-to-run. Two
> throughput columns, both higher-is-better: **`MB/s`** counts bytes/second, so it
> folds in the ~13 % wire-size gap; **`msg/s`** counts messages/second — the
> **size-neutral** per-message codec speed (see [#85]). The columns comparable
> *across* rows are **wire size** and the **per-target ratios**. Each timed
> iteration re-encodes the message it just decoded (`encode(decode(blob))`, see
> [#86]), so a freshly parsed instance makes protobuf pay its size pass every encode
> — no memoization discount from an artificial reuse loop.

[#85]: https://github.com/sofa-buffers/arena/issues/85
[#86]: https://github.com/sofa-buffers/arena/issues/86

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
**434-byte** wire, and every protobuf-family baseline emits the same **494-byte** wire.

### The wire format

For the **same message and the same values**, SofaBuffers serializes to a smaller,
canonical wire — and does so **identically in every language**. That size fact is
constant across every row below (the byte-identity gate enforces it), so it is
summarized once here instead of repeated as two columns per table:

| format | wire size | vs. protobuf |
|---|--:|--:|
| **SofaBuffers** | **434 B** | **1.14× smaller** — −60 B, ~13 % more compact |
| Protocol Buffers | 494 B | — |

The throughput tables therefore drop the per-row `sofab size` / `proto size`
columns and keep only the size **advantage** (`1.14×`).

### Maxspeed — throughput

| language | sofab MB/s | proto MB/s | sofab msg/s | proto msg/s | **size** adv | **MB/s** adv | **msg/s** adv |
|---|--:|--:|--:|--:|:--:|:--:|:--:|
| C++        | 324.9 | 257.4 | 748 600 | 521 095 | **1.14×** | **1.26×** | **1.44×** |
| Rust       | 349.2 | 241.6 | 804 644 | 489 058 | **1.14×** | **1.45×** | **1.65×** |
| Zig        | 548.5 | 262.6 | 1 263 730 | 531 549 | **1.14×** | **2.09×** | **2.38×** |
| Go         | 143.4 | 138.7 | 330 318 | 280 804 | **1.14×** | **1.03×** | **1.18×** |
| C#         | 180.1 | 125.4 | 414 875 | 253 868 | **1.14×** | **1.44×** | **1.63×** |
| Java       | 229.2 | 248.7 | 528 083 | 503 387 | **1.14×** | 0.92× | **1.05×** |
| TypeScript · Node/V8 † |  37.7 |  74.9 |  86 800 | 151 584 | **1.14×** | 0.50× | 0.57× |
| TypeScript · Bun/JSC † |  38.1 |  52.4 |  87 874 | 106 030 | **1.14×** | 0.73× | 0.83× |
| Python ‡   |  18.4 | 224.3 |  42 374 | 454 055 | **1.14×** | 0.08× | 0.09× |

***On the size-neutral per-message metric (`msg/s`), every compiled and JIT language now
beats protobuf** — Zig by 2.4×, and even Java edges ahead (1.05×) after the round-trip fix
([#86]). The wire is ~13 % smaller everywhere, so `MB/s` — which folds in that byte gap —
reads a touch lower than the per-message win (Java lands at 0.92× there). adv >1 →
SofaBuffers ahead; best-of-5, comparable only within a row.*

- † The two **TypeScript** rows are the **identical** codec on the two JavaScript
engines — Node (V8) and Bun (JavaScriptCore)

- ‡ **Python is slowest (0.08× MB/s, 0.09× msg/s), and it's not a fallback.** Python trails because
protobuf-python is a thin shell over Google's C **`upb`** engine while SofaBuffers
keeps a **per-field Python driver** — it runs the native Cython accelerator
(`sofab.IMPL == "native"`), not a fallback. See
[`languages/python/README.md`](languages/python/README.md) for the full profile
(runtime verification + callgrind attribution table).*

### Embedded — throughput (host build of the embedded codecs)

Same message, same values, same timing method, **same columns** as maxspeed —
but these are the **embedded-friendly** implementations (fixed-capacity
containers, built `-Os`), so speed is an interesting factor here, **not the
ranking metric** (that is footprint, below).

| opponent | sofab MB/s | proto MB/s | sofab msg/s | proto msg/s | **size** adv | **MB/s** adv | **msg/s** adv |
|---|--:|--:|--:|--:|:--:|:--:|:--:|
| sofab-c-embedded vs. protobuf-c    | 130.1 | 323.6 | 299 817 | 655 103 | **1.14×** | 0.40× | 0.46× |
| sofab-c-embedded vs. nanopb        | 130.1 |  61.3 | 299 817 | 124 012 | **1.14×** | **2.12×** | **2.42×** |
| sofab-rust-embedded vs. micropb    | 154.3 | 127.8 | 355 447 | 258 719 | **1.14×** | **1.21×** | **1.37×** |
| sofab-cpp-embedded vs. embeddedproto | 135.4 |  58.6 | 312 069 | 118 590 | **1.14×** | **2.31×** | **2.63×** |

***Even built for size, the SofaBuffers codecs outrun every embedded protobuf
baseline on the size-neutral `msg/s` metric** (2.4× vs nanopb, 2.6× vs EmbeddedProto,
1.4× vs micropb) — only the desktop-class `protobuf-c` is faster.*

### Embedded — bare-metal footprint (`--gc-sections` link delta; **lower is better**)

What the codec **actually adds to firmware**: cross-compiled `-Os -flto -DNDEBUG`
(Rust: `#![no_std]` staticlib, `opt-level=z` + LTO), linked into a minimal program
with `-Wl,--gc-sections`, reported as *codec program − empty baseline*. Build-only
targets — the binaries are never executed. Ranked by **footprint** — everything
that ends up in flash: `.text` + `.rodata` + `.data` (the `.data` initializer
images live in flash and are copied to RAM at boot; `.bss` is RAM-only).

The embedded corelibs — [`corelib-c-cpp`](https://github.com/sofa-buffers/corelib-c-cpp)
(C object API + C++ wrapper) and [`corelib-rs-no-std`](https://github.com/sofa-buffers/corelib-rs-no-std)
(`#![no_std]`, no-alloc) — expose config options to shrink the footprint even
further below the numbers reported here.

| target (ISA) | impl | `.text` | `.rodata` | `.data` | **footprint** | static-RAM |
|---|---|--:|--:|--:|--:|--:|
| **c-cortex-m** (thumbv7e-m+fp) | sofab | 3 400 | 344 | 0 | **3 744** | 0 |
| | nanopb | 5 676 | 936 | 0 | 6 612 | 0 |
| **cpp-cortex-m** (thumbv7e-m+fp) | sofab | 6 716 | 156 | 80 | **6 952** | 132 |
| | embeddedproto | 8 344 | 904 | 80 | 9 328 | 96 |
| **rust-cortex-m** (thumbv7e-m+fp) | sofab | 6 096 | 330 | 0 | **6 426** | 0 |
| | micropb | 8 248 | 261 | 0 | 8 509 | 0 |
| **c-riscv** (rv32imac) | sofab | 3 400 | 488 | 0 | **3 888** | 0 |
| | nanopb | 6 384 | 1 112 | 0 | 7 496 | 0 |
| **cpp-riscv** (rv32imac) | sofab | 6 040 | 300 | 76 | **6 416** | 420 |
| | embeddedproto | 8 824 | 1 012 | 76 | 9 912 | 388 |
| **rust-riscv** (rv32imac) | sofab | 6 912 | 386 | 0 | **7 298** | 0 |
| | micropb | 9 696 | 393 | 0 | 10 089 | 0 |

***SofaBuffers wins all six rows — three languages × two ISAs** (1.32×–1.93×
less flash than the smallest protobuf alternative).*

### The big picture

- **Smaller on the wire, in every language.** The SofaBuffers encoding is about
  13 % more compact than protobuf for the same message — the same win everywhere,
  not a per-language accident.
- **Faster than protobuf per message in every compiled and JIT language.** The gap
  was never the wire format but the per-message code above the byte codec; with
  that tuned — and with the round trip chained so protobuf pays its size pass every
  encode ([#86]) — Zig, C++, Rust, C#, Go **and Java** all run ahead of Google's
  mature runtimes on the size-neutral `msg/s` metric — Zig by ~2.4×, Java by a slim
  1.05×. Only TypeScript trails (tracking JS-engine maturity, not the format), and
  Python is the lone outlier, because its protobuf baseline is a thin shell
  over Google's C `upb` engine while SofaBuffers still drives every field from
  Python. *(How the codegen was tuned: [`docs/perf/bottlenecks.md`](docs/perf/bottlenecks.md).)*
- **The smallest embedded codec in every language, on both ISAs** — measured the
  way firmware actually pays: the flash a codec adds once the linker drops what it
  never calls. It undercuts nanopb, EmbeddedProto and micropb across the board,
  with less static RAM, no heap, and — even built for size — more throughput than
  any of them. *(A naïve object-sum flatters template-heavy libraries by counting
  code `--gc-sections` later discards; the link-delta counts only what ships.)*
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
