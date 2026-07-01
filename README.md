<p align="center"><b>SofaBuffers Arena — Benchmark or Bust</b></p>

# SofaBuffers vs. Protobuf, in every language

The original [sofabuffers-comparison](https://github.com/Andste82/sofabuffers-comparison)
was a **C/C++ arena**: it built a handful of serialization libraries against one
identical message and measured who was leanest and fastest. This repo takes that
idea and makes it **multi-language**.

The question here is narrower and sharper:

> For the **same message**, with the **same values**, how does **SofaBuffers**
> stack up against **Protocol Buffers** — in **C, C++, Rust, Go, C#, Java,
> TypeScript and Python**?

Every language gets **two** targets — one SofaBuffers, one protobuf — that encode
and decode the exact same `FullScaleExample` message and report their wire size
and encode+decode throughput in a single uniform format. Then one runner collects
all of it into a single side-by-side picture.

## The message (identical everywhere)

One message definition, expressed twice — once for each generator:

- SofaBuffers: [`schema/message.sofab.yaml`](schema/message.sofab.yaml) → compiled by
  [`sofabgen`](https://github.com/sofa-buffers/generator) to typed code against each
  language's [corelib](https://github.com/sofa-buffers).
- Protobuf: [`schema/message.proto`](schema/message.proto) → compiled by `protoc`
  to typed code against each language's protobuf runtime.

It is a deliberately "full scale" message — every scalar width, floats, strings,
raw bytes, eight numeric arrays, a nested struct, an array-of-structs, and an
array of Unicode strings. The single source of truth for the field **values**
every target fills is [`schema/STATE.md`](schema/STATE.md)
(machine form: [`schema/state.json`](schema/state.json)).

## How the comparison is kept fair

Every target — all 16 of them — obeys one [benchmark contract](docs/BENCH.md) and
emits one machine-readable line:

```
BENCH lang=<lang> impl=<sofab|protobuf> serialized_bytes=<n> iters=<n> cpu_time_s=<f> throughput_mbs=<f> sha256=<hex>
```

- **Same message, same values.** All fields identical across all targets.
- **Warm-up + self-check outside the timed loop.** One round-trip up front captures
  the wire size and SHA-256 and asserts the decoded message re-encodes to identical
  bytes; a target that fails exits non-zero.
- **Only encode + decode is timed.** Buffers and decode targets are hoisted out of
  the loop where the language allows; construction, JSON parsing and I/O are not
  counted. Within a language, SofaBuffers and protobuf use the **identical timing
  method and iteration count**.
- **A cross-language byte-identity gate.** Because every SofaBuffers corelib speaks
  the same wire format, and protobuf is deterministic for this message, the runner
  asserts that *every* `sofab` target emits the same bytes and *every* `protobuf`
  target emits the same bytes. A drifted fill in any language is caught automatically.

> **Reading the throughput numbers.** `throughput_mbs` is an encode+decode
> throughput on **this host** and is only meaningful **within a language** (each
> language runs on a completely different runtime — a JIT, a VM, an interpreter,
> native code). The columns that *are* directly comparable across languages are
> **wire size** (identical by construction) and the **SofaBuffers-vs-protobuf
> ratios** within each language.

## Quick start

You need the multi-language toolchain (C/C++, Rust, Go, .NET, JDK+Maven, Node,
Python + protobuf, and `protoc`). The [`.devcontainer`](.devcontainer) ships all of
it — `./.devcontainer/start.sh` builds and drops you into the image.

```bash
# one-time: fetch sofabgen + the corelibs + the python protobuf toolchain
./scripts/bootstrap.sh

# build every target for every language, run them, print the big picture
./scripts/run_benchmark.sh

# handy variants
LANGS="rust go cpp" ./scripts/run_benchmark.sh   # a subset
BENCH_ITERS=100000 ./scripts/run_benchmark.sh    # fewer iterations
./scripts/run_benchmark.sh --no-setup            # reuse existing builds
```

`run_benchmark.sh` is the single entry point: per language it runs
`languages/<lang>/setup.sh` (generate + build) then `languages/<lang>/bench.sh`
(run both impls), parses every `BENCH` line, enforces the byte-identity gate, and
prints — and writes to `results/RESULTS.txt` — the comparison below.

<!-- RESULTS:BEGIN -->
## Results

Every target passes the byte-identity gate: all SofaBuffers targets emit the same
**436-byte** wire (the C object API is **434 B** — see note), and all protobuf
targets emit the same **494-byte** wire.

| language | sofab size | proto size | sofab MB/s | proto MB/s | **size** advantage | **speed** advantage |
|---|--:|--:|--:|--:|:--:|:--:|
| C          | 434 | 494 | 136.7 | 221.5 | **1.14×** | 0.62× |
| C++        | 436 | 494 | 210.5 | 177.9 | **1.13×** | **1.18×** |
| Rust       | 436 | 494 | 165.2 | 152.2 | **1.13×** | **1.09×** |
| Go         | 436 | 494 |  33.7 |  86.4 | **1.13×** | 0.39× |
| C#         | 436 | 494 |  85.5 |  98.9 | **1.13×** | 0.86× |
| Java       | 436 | 494 | 111.5 | 155.7 | **1.13×** | 0.72× |
| TypeScript | 436 | 494 |  22.1 |  41.0 | **1.13×** | 0.54× |
| Python     | 436 | 494 |  17.4 | 143.5 | **1.13×** | 0.12× |

*size advantage = protobuf_bytes / sofab_bytes (>1 → SofaBuffers smaller). speed
advantage = sofab_MBps / protobuf_MBps (>1 → SofaBuffers faster). Throughput is
encode+decode MB/s on one dev host; it is machine-dependent, varies run-to-run,
and is meaningful **only within a language** — never read a MB/s number across two
rows. Wire size and the per-language ratios are the stable, comparable columns.*

### The big picture

- **On the wire, SofaBuffers wins everywhere — consistently ~13% smaller** (494 →
  436 bytes), and the C object API is leaner still at 434 B. Same message, same
  values, every language: SofaBuffers is the smaller encoding, full stop.
- **On speed, it's a split decided by runtime maturity, not by the format:**
  - In **C++ and Rust, SofaBuffers is faster** — **C++ 1.18×**, **Rust 1.09×**.
    Here the lean wire format and low-overhead codegen turn into fewer cycles.
  - **Elsewhere, Google's protobuf runtimes lead** — a decade of hand-tuning,
    C-accelerated fast paths, and codegen honed for each VM. The gap runs from
    close (**C# 0.86×**, **Java 0.72×**) to wide (**Go 0.39×**, **TypeScript
    0.54×**), and is largest in **Python** (**0.12×**), where protobuf calls into a
    C extension. These gaps track corelib maturity, not the wire format.
  - **C** is the interesting inversion: `protobuf-c` is a famously tight C
    implementation and edges out the SofaBuffers object API (a runtime-descriptor
    codec built for footprint/embedded flexibility, not peak throughput) at
    **0.62×**.
- **Corelib tuning moves the needle.** Two recent optimizations narrowed the
  biggest higher-level gaps without touching the wire format: **TypeScript** rose
  from **~0.38× to 0.54×** — pool the encode buffer via `OStream.reset()` instead
  of allocating one per message, plus a single-shot contiguous-decode path that
  skips the chunk-accumulator `Map`s — and **Python** jumped from **~0.02× to
  0.12×** by building corelib-py's native Cython accelerator instead of the
  pure-Python fallback (its earlier ~60× deficit is now ~8×).

- **Bottom line.** SofaBuffers already delivers its headline promise — a **smaller
  wire in every language** — and is **faster where the language is close to the
  metal** (C++, Rust). The higher-level corelibs are where throughput work remains,
  and the TypeScript and Python gains show that gap is a corelib-maturity artifact,
  not a format limitation.

> **Note — why C is 434 B.** The C target is the SofaBuffers *object API*
> (`corelib-c-cpp`), a runtime-descriptor codec for constrained/embedded use. It
> omits the single empty string in `string_array` (a deliberate leanness
> optimization), so its wire is 2 bytes smaller — exactly the difference the
> original C/C++ arena documented. It is a *correct, expected* variant, and the
> gate checks C against 434 B specifically. No corelib was modified to reach these
> numbers.
<!-- RESULTS:END -->

## Repository layout

```
schema/            the message: message.sofab.yaml, message.proto, STATE.md, state.json
docs/BENCH.md      the uniform benchmark contract every target obeys
languages/
  <lang>/
    setup.sh       generate sofab + protobuf code and build both targets (idempotent)
    bench.sh       run both targets, print the two BENCH lines
    sofab/         SofaBuffers driver + generated code
    protobuf/      protobuf driver + generated code
  common/          shared SHA-256 helper for the C/C++ targets
scripts/
  bootstrap.sh     fetch sofabgen + corelibs + python protobuf venv
  run_benchmark.sh build + run everything, enforce the gate, print the big picture
.devcontainer/     the multi-language dev image (Dockerfile + build/start/attach)
tools/             sofabgen + python venv (bootstrapped, gitignored)
vendor/            the SofaBuffers corelibs (cloned, gitignored)
```

## Credits

- **SofaBuffers** — the format, generator and corelibs: https://github.com/sofa-buffers
- **Protocol Buffers** — https://protobuf.dev
- The original C/C++ arena this grew out of:
  https://github.com/Andste82/sofabuffers-comparison
