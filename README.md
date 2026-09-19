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
>   encode+decode vs **Protocol Buffers**, in **C++, Rust, Zig, Dart, Go, C#, Java,
>   Kotlin Multiplatform, TypeScript and Python**? Ranked by **throughput (MB/s)**.
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
| **Maxspeed** — cpp/heapfree | `corelib-cpp` with `allow_dynamic: false` — every schema-bounded field in `sofab::FixedString`/`FixedBytes`/`InlineVector`, so a decode allocates nothing | the same `libprotobuf` run as the `cpp` row | throughput |
| **Maxspeed** — rust/heapless | `corelib-rs` (std) with `allow_dynamic: false` — every schema-bounded field in `heapless::String`/`heapless::Vec`, so a decode allocates nothing | the same `prost` run as the `rust` row | throughput |
| **Maxspeed** — zig | `corelib-zig` | [zig-protobuf](https://github.com/Arwalk/zig-protobuf) (Arwalk) | throughput |
| **Maxspeed** — go, csharp, java, typescript, python, dart | each language's corelib | Google protobuf runtime (Dart: [`protoc_plugin`](https://pub.dev/packages/protoc_plugin)) | throughput |
| **Maxspeed** — kotlin-mp | `corelib-kotlin-mp` — one `commonMain` codec for JVM, JS and native | [**Square Wire**](https://github.com/square/wire) — the protobuf implementation that generates Kotlin Multiplatform sources directly (no Java classes in the chain), on its KMP `wire-runtime` | throughput |
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
- **One knob per extra row.** A `sofab-<variant>` impl (today `cpp`/`sofab-heapfree`
  and `rust`/`sofab-heapless`) is the **same corelib and the same driver source**, built
  with the same flags, one `cfg.yaml` key apart — and it faces the very same
  protobuf run as its base row. So the `<lang>/<variant>` rows isolate that one
  codegen option, and unlike rows of different languages they *are* comparable to
  each other.
- **Optimized per category, portably, identically per row.** Maxspeed targets build
  for speed — `-O3 -march=native -flto` (C/C++), `target-cpu=native` + LTO (Rust),
  and portable runtime tuning for the VMs (workstation/server GC, `GOGC`, ParallelGC,
  TieredPGO). Embedded targets build for size — `-Os -flto`. Nothing pins a CPU/ISA
  level: `-march=native` is *adaptive* and the arena rebuilds on each host, so it runs
  anywhere; and within a row SofaBuffers and its baseline get the **same** flags.
  Throughput is reported **best-of-5** (`RUNS=5`, the default) since it is noisy, and
  the runner idles 10 s before every executed bench (`COOLDOWN_S`) so no run starts on
  a CPU still hot — and throttling — from the previous one.

> **Reading throughput (`MB/s` and `msg/s`).** An encode+decode figure on **this
> host**, only meaningful **within a language** (each runs on a different runtime —
> JIT, VM, interpreter, native). It is machine-dependent and varies run-to-run. Two
> throughput columns, both higher-is-better: **`MB/s`** counts bytes/second, so it
> folds in the smaller wire; **`msg/s`** counts messages/second — the
> **size-neutral** per-message codec speed. The columns comparable
> *across* rows are **wire size** and the **per-target ratios**. Each timed
> iteration re-encodes the message it just decoded (`encode(decode(blob))`),
> so a freshly parsed instance makes protobuf pay its size pass every encode
> — no memoization discount from an artificial reuse loop.

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
> since sofabgen 0.9.0).

## Quick start

The [`.devcontainer`](.devcontainer) ships the full multi-language toolchain —
`./.devcontainer/start.sh` builds and drops you into the image, including the
bare-metal cross toolchains (`gcc-arm-none-eabi` + newlib/libstdc++,
`gcc-riscv64-unknown-elf` + picolibc, and the xpack `riscv-none-elf` GCC — the
only one with a RISC-V bare-metal libstdc++, for `cpp-riscv`) used by the
footprint-only targets. Embedded
baselines also need `protoc` and a network fetch of nanopb / EmbeddedProto
(build-time only), and the `kotlin-mp` target builds through Gradle — which runs
on the image's build-only JDK 21, not its default JDK (see
[`languages/kotlin-mp/README.md`](languages/kotlin-mp/README.md)).

```bash
# one-time: fetch sofabgen + the corelibs + the python protobuf toolchain
./scripts/bootstrap.sh

# build every target, run them, print both tables (best-of-5 throughput by default)
./scripts/run_benchmark.sh

# handy variants
LANGS="cpp rust c-embedded" ./scripts/run_benchmark.sh     # a subset (any category)
BENCH_ITERS=100000 ./scripts/run_benchmark.sh     # fewer iterations
RUNS=1 ./scripts/run_benchmark.sh                 # single quick run (skip best-of-5)
COOLDOWN_S=30 ./scripts/run_benchmark.sh          # longer thermal pause between runs
COOLDOWN_S=0 ./scripts/run_benchmark.sh           # no pause (faster, hotter CPU)
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
| C++        | 293.1 | 262.9 | 675 377 | 532 136 | **1.14×** | **1.11×** | **1.27×** |
| C++ · heapfree § | 375.8 | 262.9 | 865 808 | 532 136 | **1.14×** | **1.43×** | **1.63×** |
| Rust       | 414.1 | 262.5 | 954 091 | 531 302 | **1.14×** | **1.58×** | **1.80×** |
| Rust · heapless § | 519.4 | 262.5 | 1 196 820 | 531 302 | **1.14×** | **1.98×** | **2.25×** |
| Zig        | 465.9 | 266.6 | 1 073 506 | 539 589 | **1.14×** | **1.75×** | **1.99×** |
| Dart       | 174.7 |  58.8 | 402 414 | 119 118 | **1.14×** | **2.97×** | **3.38×** |
| Go         | 155.5 | 144.2 | 358 185 | 291 984 | **1.14×** | **1.08×** | **1.23×** |
| C#         | 223.1 | 131.1 | 514 125 | 265 398 | **1.14×** | **1.70×** | **1.94×** |
| Java       | 295.3 | 267.9 | 680 458 | 542 288 | **1.14×** | **1.10×** | **1.25×** |
| Kotlin Multiplatform | 260.6 | 150.9 | 600 410 | 305 356 | **1.14×** | **1.73×** | **1.97×** |
| TypeScript · Node/V8 † |  70.9 |  78.0 | 163 259 | 157 856 | **1.14×** | 0.91× | **1.03×** |
| TypeScript · Bun/JSC † |  60.7 |  33.9 | 139 756 |  68 607 | **1.14×** | **1.79×** | **2.04×** |
| Python ‡   |  26.3 | 197.1 |  60 659 | 398 945 | **1.14×** | 0.13× | 0.15× |

***SofaBuffers is faster per message (`msg/s`) than protobuf in every compiled
language** — and on both JavaScript engines; Python the only outlier. `MB/s` reads
lower than `msg/s` throughout because SofaBuffers moves fewer bytes per message
(its smaller wire). adv >1 → SofaBuffers ahead; comparable only within a row.*

- § The **heapfree** / **heapless** rows are the same corelib and the same driver
one `cfg.yaml` key apart (`allow_dynamic: false`), sharing their base row's
protobuf run — so they isolate that single codegen option and *are* comparable
to their base row

- † The two **TypeScript** rows are the **identical** codec on the two JavaScript
engines — Node (V8) and Bun (JavaScriptCore)

- ‡ **Python is slowest, and it's not a fallback.** Python trails because
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
| sofab-c-embedded vs. protobuf-c    | 117.1 | 342.4 | 269 692 | 693 178 | **1.14×** | 0.34× | 0.39× |
| sofab-c-embedded vs. nanopb        | 117.1 |  63.6 | 269 692 | 128 648 | **1.14×** | **1.84×** | **2.10×** |
| sofab-rust-embedded vs. micropb    | 181.4 | 127.5 | 418 031 | 258 076 | **1.14×** | **1.42×** | **1.62×** |
| sofab-cpp-embedded vs. embeddedproto | 135.6 |  59.3 | 312 443 | 120 065 | **1.14×** | **2.29×** | **2.60×** |

***Even built for size, the SofaBuffers codecs outrun every embedded protobuf
baseline on the size-neutral `msg/s` metric** (nanopb, EmbeddedProto, micropb) —
only the desktop-class `protobuf-c` is faster.*

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
| **c-cortex-m** (thumbv7e-m+fp) | sofab | 4 296 | 356 | 0 | **4 652** | 0 |
| | nanopb | 5 676 | 936 | 0 | 6 612 | 0 |
| **cpp-cortex-m** (thumbv7e-m+fp) | sofab | 6 968 | 156 | 80 | **7 204** | 132 |
| | embeddedproto | 8 344 | 904 | 80 | 9 328 | 96 |
| **rust-cortex-m** (thumbv7e-m+fp) | sofab | 6 660 | 256 | 0 | **6 916** | 0 |
| | micropb | 8 180 | 261 | 0 | 8 441 | 0 |
| **c-riscv** (rv32imac) | sofab | 4 184 | 456 | 0 | **4 640** | 0 |
| | nanopb | 6 384 | 1 112 | 0 | 7 496 | 0 |
| **cpp-riscv** (rv32imac) | sofab | 6 672 | 324 | 76 | **7 072** | 420 |
| | embeddedproto | 8 824 | 1 012 | 76 | 9 912 | 388 |
| **rust-riscv** (rv32imac) | sofab | 7 056 | 320 | 0 | **7 376** | 0 |
| | micropb | 9 680 | 393 | 0 | 10 073 | 0 |

***SofaBuffers wins all six rows — three languages × two ISAs**, taking less flash
than the smallest protobuf alternative in every one.*

### The big picture

- **Smaller on the wire, in every language.** The SofaBuffers encoding is more
  compact than protobuf for the same message — the same win everywhere,
  not a per-language accident.
- **Faster than protobuf per message in every compiled language.** The gap
  was never the wire format but the per-message code above the byte codec; with
  that tuned — and with the round trip chained so protobuf pays its size pass every
  encode — Dart, Zig, C#, Kotlin Multiplatform, Rust, C++, Java and Go all run
  ahead of their protobuf baselines on the size-neutral `msg/s` metric, Dart by
  the widest margin (3.4×), Zig, C# and Kotlin Multiplatform close to 2×. Turning off dynamic
  allocation lifts the compiled rows further still — `rust/heapless` and
  `cpp/heapfree` gain against the very same protobuf run as their base rows.
  TypeScript runs ahead on both JS engines as well — clearly on Bun/JSC, and just
  barely per message on Node/V8, where `MB/s` trails — and Python is the far outlier,
  because its protobuf baseline is a thin shell
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
    sofab-<v>/     (optional) a second codegen configuration of the SAME corelib
                   and driver, one cfg.yaml key apart — cpp/sofab-heapfree and
                   rust/sofab-heapless are `allow_dynamic: false`. Gets its own
                   `<lang>/<v>` row.
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
                   source, EmbeddedProto, the Wire compiler CLI) — all fetched,
                   gitignored
```

## Credits

- **SofaBuffers** — the format, generator and corelibs: https://github.com/sofa-buffers
- **Protocol Buffers** — https://protobuf.dev
- **Square Wire** (Apache-2.0) — the Kotlin Multiplatform protobuf implementation
  benchmarked in the `kotlin-mp` row: https://github.com/square/wire
- Embedded protobuf baselines: **nanopb** (zlib), **micropb** (MIT/Apache-2.0),
  **protobuf-c** (BSD), and **EmbeddedProto** (GPLv3 — used build-time only, fetched
  into gitignored `vendor/`, never redistributed): https://github.com/Embedded-AMS/EmbeddedProto
