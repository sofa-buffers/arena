<p align="center"><b>SofaBuffers Arena — Benchmark or Bust</b></p>

# SofaBuffers vs. Protobuf, in every language

The original [sofabuffers-comparison](https://github.com/Andste82/sofabuffers-comparison)
was a **C/C++ arena**: it built a handful of serialization libraries against one
identical message and measured who was leanest and fastest. This repo takes that
idea and makes it **multi-language** — and splits it into **two categories** so we
compare like with like instead of mixing goals:

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
  Throughput is reported **best-of-5** (`RUNS=5`) since it is noisy.

> **Reading throughput (`MB/s`).** An encode+decode figure on **this host**, only
> meaningful **within a language** (each runs on a different runtime — JIT, VM,
> interpreter, native). It is machine-dependent and varies run-to-run. The columns
> comparable *across* rows are **wire size** and the **per-target ratios**.

> **Reading footprint (`.text`/RAM).** The **interim** metric is an *object-sum*:
> each library's own compiled code (`-Os`, **no libc**) section-summed with `size`.
> This counts the **whole library**, so it over-counts a generic runtime that
> `--gc-sections` would trim in real firmware — it favors code-generation
> (SofaBuffers) over generic runtimes. The **fair** metric is a bare-metal
> (`arm-none-eabi`, newlib-nano, `--gc-sections`) build; that is a **TODO**, and
> until then `rust-embedded` footprint is left blank (a host object-sum for Rust is
> dominated by std, not codec).

## Quick start

The [`.devcontainer`](.devcontainer) ships the full multi-language toolchain —
`./.devcontainer/start.sh` builds and drops you into the image. Embedded baselines
also need `protoc`, the ARM cross-toolchain (`gcc-arm-none-eabi`, for the future
footprint metric), and a network fetch of nanopb / EmbeddedProto (build-time only).

```bash
# one-time: fetch sofabgen + the corelibs + the python protobuf toolchain
./scripts/bootstrap.sh

# build every target, run them, print both tables
./scripts/run_benchmark.sh

# handy variants
LANGS="cpp rust c-embedded" ./scripts/run_benchmark.sh     # a subset (any category)
BENCH_ITERS=100000 ./scripts/run_benchmark.sh     # fewer iterations
RUNS=5 ./scripts/run_benchmark.sh                 # best-of-5 throughput (recommended)
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
| C++        | 436 | 494 | 229.9 | 176.5 | **1.13×** | **1.30×** |
| Rust       | 436 | 494 | 174.7 | 192.3 | **1.13×** | 0.91× |
| Go         | 436 | 494 |  44.4 | 111.0 | **1.13×** | 0.40× |
| C#         | 436 | 494 |  91.8 | 116.1 | **1.13×** | 0.79× |
| Java       | 436 | 494 | 133.6 | 205.8 | **1.13×** | 0.65× |
| TypeScript | 436 | 494 |  25.4 |  38.8 | **1.13×** | 0.66× |
| Python     | 436 | 494 |  17.1 | 153.9 | **1.13×** | 0.11× |

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
| **cpp-embedded** | sofab | 436 | 12 187 | 1 597 | 592 | 1.00× |
| | **embeddedproto** | 494 | **3 276** | 261 | 352 | **0.27×** |
| **rust-embedded** | sofab | 436 | — | — | — | *(pending ARM)* |
| | micropb | 494 | — | — | — | |

*Footprint is the interim object-sum (whole library, no libc). `.text vs sofab` >1
means the baseline carries more code than SofaBuffers.*

### The big picture

- **On the wire, SofaBuffers wins everywhere — consistently ~13% smaller** (494 →
  436 B; the C object API is leaner still at 434 B). Same message, every language.
- **Maxspeed: a split decided by runtime maturity, not the format** (all targets
  built/tuned for speed — see settings note above).
  - **C++: SofaBuffers is faster — 1.30×.** A lean wire format plus low-overhead
    codegen, and `-O3 -march=native -flto` vectorizes the hot loops.
  - **Rust: near-parity, protobuf edges ahead (0.91×).** Both got `target-cpu=native`
    + LTO; `prost`'s heavily-tuned generated code benefits a touch more (it led ~1.06×
    before the aggressive flags — the optimization helped prost more than sofab-rust).
  - **Elsewhere Google's protobuf runtimes lead** — a decade of hand-tuning and
    per-VM codegen. The gap ranges from close (**C# 0.79×**, **Java 0.65×**,
    **TypeScript 0.66×**) to wide (**Go 0.40×**, **Python 0.11×** — where protobuf
    calls a C extension). These track corelib maturity, not the wire format.
  - **Corelib tuning moves the needle:** earlier work lifted **TypeScript** (pool the
    encode buffer via `OStream.reset()` + a single-shot contiguous-decode path) and
    **Python** (build corelib-py's native Cython accelerator) — evidence the gaps are
    a maturity artifact, not a format limit.
- **Embedded: SofaBuffers wins in C, loses the C++ wrapper — honestly.**
  - **C:** the SofaBuffers object API has the **smallest codec** — **5.9 KB `.text`**,
    ~1.6× under nanopb and ~4.4× under `protobuf-c` (which also needs a heap).
  - **cpp-embedded:** **EmbeddedProto is smaller** (3.3 KB) than the SofaBuffers C++
    wrapper (12.2 KB, **0.27×**). The wrapper's C++ template layer over the C object
    API costs code; EmbeddedProto is purpose-built for minimal `.text`. A real
    result, reported as-is.
  - **rust-embedded:** wire + throughput land (sofab `corelib-rs-no-std` vs micropb,
    both no_std/no-alloc); the **footprint number is deferred** to the bare-metal
    metric — a host object-sum for Rust is std-dominated and not a codec comparison.
- **Caveat that matters.** The embedded ranking is sensitive to methodology: the
  interim object-sum favors code-generation over generic runtimes; a bare-metal
  `--gc-sections` build (the TODO) is the fair, firmware-representative number.

> **Note — why C is 434 B.** The C target is the SofaBuffers *object API*
> (`corelib-c-cpp`), a runtime-descriptor codec for constrained/embedded use. It
> omits the single empty string in `string_array` (a deliberate leanness
> optimization), so its wire is 2 bytes smaller. It is a *correct, expected* variant,
> and the gate checks C against 434 B specifically. (The C++ wrapper of the same
> corelib encodes all five strings, so `cpp-embedded` is 436 B.)
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
    footprint.sh   (embedded) object-sum the codec sections
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
- The original C/C++ arena this grew out of:
  https://github.com/Andste82/sofabuffers-comparison
