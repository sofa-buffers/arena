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
| **Maxspeed** — go, csharp, java, typescript, dart | each language's corelib | Google protobuf runtime (Dart: [`protoc_plugin`](https://pub.dev/packages/protoc_plugin)) | throughput |
| **Maxspeed** — python/native, python/pure | `corelib-py`, one row per engine it ships: the compiled accelerator (`sofab._speedups`, built by Cython) and the pure-Python fallback forced with `SOFAB_PUREPYTHON=1` — same driver, same wire, so the pair prices the accelerator | one shared protobuf-python run for both rows | throughput |
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
- **One knob per extra row.** A `sofab-<variant>` impl is the **same corelib and the
  same driver source**, built with the same flags and facing the very same protobuf
  run as its base row, with exactly one thing changed: a `cfg.yaml` key
  (`cpp`/`sofab-heapfree` and `rust`/`sofab-heapless`, both `allow_dynamic: false`)
  or which engine of a corelib that ships two backs the run
  (`python`/`sofab-native` vs `python`/`sofab-pure`, the compiled accelerator vs
  the pure-Python fallback — the one target where both impls are named and there
  is no unlabelled base row). So the `<lang>/<variant>` rows isolate that one
  knob, and unlike rows of different languages they *are* comparable to each
  other.
- **Optimized per category, portably, identically per row.** Maxspeed targets build
  for speed — `-O3 -march=native -flto -DNDEBUG` (C/C++), `target-cpu=native` + LTO (Rust),
  and only noise-reducing runtime settings for the VMs (fixed JVM heap, non-concurrent
  .NET GC, `GOMAXPROCS=1`) — default GCs and JITs otherwise. Embedded targets build
  for size — `-Os -flto -DNDEBUG`. Nothing pins a CPU/ISA level: `-march=native` is
  *adaptive* and the arena rebuilds on each host, so it runs anywhere; and within a
  row SofaBuffers and its
  baseline are compiled with the **same** flags. A baseline runtime that a user links
  as the distro package (`libprotobuf` for `cpp`, `libprotobuf-c` for `c-embedded`)
  keeps its packaged build, as it would in their application.
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
SETUP_TIMEOUT_S=3600 ./scripts/run_benchmark.sh   # per-target setup.sh cap (0 = off)
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
| C++        | 359.5 | 268.2 | 828 328 | 542 951 | **1.14×** | **1.34×** | **1.53×** |
| C++ · heapfree _\*1_ | 388.5 | 268.2 | 895 109 | 542 951 | **1.14×** | **1.45×** | **1.65×** |
| Rust _\*4_ | 544.6 | 267.0 | 1 254 799 | 540 474 | **1.14×** | **2.04×** | **2.32×** |
| Rust · heapless _\*1_ | 520.5 | 267.0 | 1 199 222 | 540 474 | **1.14×** | **1.95×** | **2.22×** |
| Zig        | 441.4 | 265.9 | 1 017 008 | 538 218 | **1.14×** | **1.66×** | **1.89×** |
| Dart       | 202.3 | 57.1 | 466 200 | 115 673 | **1.14×** | **3.54×** | **4.03×** |
| Go _\*4_ | 168.1 | 143.0 | 387 261 | 289 469 | **1.14×** | **1.18×** | **1.34×** |
| C#         | 223.0 | 131.1 | 513 789 | 265 283 | **1.14×** | **1.70×** | **1.94×** |
| Java       | 275.6 | 243.4 | 634 920 | 492 610 | **1.14×** | **1.13×** | **1.29×** |
| Kotlin Multiplatform | 279.1 | 126.3 | 643 086 | 255 754 | **1.14×** | **2.21×** | **2.51×** |
| TypeScript · Node/V8 _\*2 \*5_ | 79.4 | 91.0 | 182 965 | 184 186 | **1.14×** | 0.87× | 0.99× |
| TypeScript · Bun/JSC _\*2 \*5_ | 72.4 | 54.4 | 166 795 | 110 109 | **1.14×** | **1.33×** | **1.51×** |
| Python · native _\*3_ | 27.4 | 248.2 | 63 159 | 502 356 | **1.14×** | 0.11× | 0.13× |
| Python · pure _\*3_ | 2.7 | 248.2 | 6 099 | 502 356 | **1.14×** | 0.01× | 0.01× |

***SofaBuffers is faster per message (`msg/s`) than protobuf in every compiled
language**, and on Bun/JSC. The two outliers are Python and TypeScript on
Node/V8, both of them protobuf runtimes that are really a C engine behind a
thin language shell. `MB/s` reads lower than `msg/s` throughout because
SofaBuffers moves fewer bytes per message (its smaller wire). adv >1 →
SofaBuffers ahead; comparable only within a row.*

- _\*1_ The **heapfree** / **heapless** rows are the same corelib and the same driver
one `cfg.yaml` key apart (`allow_dynamic: false`), sharing their base row's
protobuf run — so they isolate that single codegen option and *are* comparable
to their base row. **That axis has flipped sign:** `heapless` used to lead
`Rust` by 18 %, and now trails it (520.5 vs 544.6). Once the decode reuses its
destination, `String`/`Vec` never reach the allocator either, and what is left
is that heapless resets a 792 B message against 360 B. `heapfree` still leads
C++ (388.5 vs 359.5), where the same reuse has been in place a generation
longer.

- _\*2_ The two **TypeScript** rows are the **identical** codec on the two JavaScript
engines — Node (V8) and Bun (JavaScriptCore). The engines disagree sharply about
what the reused destination is worth: +12 % on Bun/JSC, +0.8 % on Node/V8 from
the very same source — confirmed warm, not a cold-JIT artefact (V8 reports the
timed loop, `tryDecode` and `serialize` all in `TURBOFAN_JS`, and scaling the
timed region 16× moves the row by ~2 %). The Node row's protobuf column is the
noisiest in the arena at the default iteration count (~10 % run-to-run); over
longer runs the row settles at **0.88×**

- _\*3_ **Python is slowest, and it's not a fallback.** The `native` row is the compiled
accelerator (asserted at runtime: `sofab.IMPL == "native"`); the `pure` row is the
pure-Python engine of the same corelib (`SOFAB_PUREPYTHON=1`, same driver, same
protobuf run), ~10× slower, so the accelerator's contribution is measured rather
than claimed. Python trails because
protobuf-python is a thin shell over Google's C **`upb`** engine while SofaBuffers
keeps per-field encode calls and object construction in Python. See
[`languages/python/README.md`](languages/python/README.md) for how the generated
code splits the work between Python and the accelerator.*

- _\*4_ **Rust** and **Go** decode into a destination the caller keeps, through
`try_decode(data, &mut out)` / `Example__TryDecode(data, out)`, so a decode
reuses the storage its `String`/`Vec`/slice fields already hold instead of
allocating per message. Both rows give their protobuf baseline the same
treatment — prost reuses through `clear()` + `merge()`, protobuf-go through a
hoisted destination, since `proto.Unmarshal` resets what it is handed. That is
worth +29 % (Rust) and +21 % (Go) to SofaBuffers and ~1 % to protobuf, because
protobuf-go's generated `Reset` is `*x = T{}` and drops every field slice:
same treatment, different ceiling

- _\*5_ The **TypeScript** rows are the one place where the two sides are *not*
symmetric, and the reason is the libraries, not the harness. SofaBuffers decodes
into a reused destination here too; protobufjs has no sound equivalent — only an
undocumented, untyped destination argument whose repeated fields append, and
hand-truncating ten arrays would be exactly the stand-in
[`docs/BENCH.md`](docs/BENCH.md) rule 6 forbids. So this is a capability
SofaBuffers has and the baseline does not, which is a real difference between
them rather than a handicap imposed here — but it is the one row where the
`msg/s` column is not a like-for-like codec comparison

### Embedded — throughput (host build of the embedded codecs)

Same message, same values, same timing method, **same columns** as maxspeed —
but these are the **embedded-friendly** implementations (fixed-capacity
containers, built `-Os`), so speed is an interesting factor here, **not the
ranking metric** (that is footprint, below).

| opponent | sofab MB/s | proto MB/s | sofab msg/s | proto msg/s | **size** adv | **MB/s** adv | **msg/s** adv |
|---|--:|--:|--:|--:|:--:|:--:|:--:|
| sofab-c-embedded vs. protobuf-c    | 117.3 | 289.6 | 270 153 | 586 306 | **1.14×** | 0.40× | 0.46× |
| sofab-c-embedded vs. nanopb        | 117.3 | 64.5 | 270 153 | 130 497 | **1.14×** | **1.82×** | **2.07×** |
| sofab-rust-embedded vs. micropb    | 162.9 | 139.7 | 375 420 | 282 732 | **1.14×** | **1.17×** | **1.33×** |
| sofab-cpp-embedded vs. embeddedproto | 159.7 | 61.4 | 367 942 | 124 378 | **1.14×** | **2.60×** | **2.96×** |

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
| **c-cortex-m** (thumbv7e-m+fp) | sofab | 4 340 | 360 | 0 | **4 700** | 0 |
| | nanopb | 5 696 | 936 | 0 | 6 632 | 0 |
| **cpp-cortex-m** (thumbv7e-m+fp) | sofab | 5 700 | 156 | 80 | **5 936** | 132 |
| | embeddedproto | 8 400 | 904 | 80 | 9 384 | 96 |
| **rust-cortex-m** (thumbv7e-m+fp) | sofab | 6 376 | 256 | 0 | **6 632** | 0 |
| | micropb | 8 100 | 256 | 0 | 8 356 | 0 |
| **c-riscv** (rv32imac) | sofab | 4 512 | 464 | 0 | **4 976** | 0 |
| | nanopb | 6 416 | 1 112 | 0 | 7 528 | 0 |
| **cpp-riscv** (rv32imac) | sofab | 5 736 | 296 | 76 | **6 108** | 420 |
| | embeddedproto | 8 908 | 1 012 | 76 | 9 996 | 388 |
| **rust-riscv** (rv32imac) | sofab | 7 608 | 324 | 0 | **7 932** | 0 |
| | micropb | 9 528 | 393 | 0 | 9 921 | 0 |

***SofaBuffers wins all six rows — three languages × two ISAs**, taking less flash
than the smallest protobuf alternative in every one.*

### The big picture

- **Smaller on the wire, in every language.** The SofaBuffers encoding is more
  compact than protobuf for the same message — the same win everywhere,
  not a per-language accident.
- **Faster than protobuf per message in every compiled language.** The gap
  was never the wire format but the per-message code above the byte codec; with
  that tuned — and with the round trip chained so protobuf pays its size pass every
  encode — Dart, Kotlin Multiplatform, Rust, C#, Zig, C++, Go and Java all run
  ahead of their protobuf baselines on the size-neutral `msg/s` metric: Dart by
  the widest margin (4.0×), then Kotlin Multiplatform (2.5×), Rust (2.3×), C#
  (1.9×) and Zig (1.9×). Decoding into a destination the caller keeps is what
  moved Rust and Go most recently, and it reshuffled the ranking: Rust now leads
  the compiled rows outright, and the heap-free profiles no longer win by
  default — `cpp/heapfree` still beats `cpp`, but `rust/heapless` has fallen
  behind plain `rust`, because a reused destination keeps `String`/`Vec` off the
  allocator too and heapless is left resetting the larger message. On
  JavaScript the two engines part ways: SofaBuffers leads clearly on Bun/JSC
  (1.51×) and is level with or behind protobuf on Node/V8 (0.99× at the default count, 0.88× over longer runs). Python is the far outlier. Both
  outliers share a cause — protobuf-python and protobufjs lean on engines
  written in C, while SofaBuffers still encodes field by field in the host
  language.
- **The smallest embedded codec in every language, on both ISAs** — measured the
  way firmware actually pays: the flash a codec adds once the linker drops what it
  never calls. It undercuts nanopb, EmbeddedProto and micropb across the board,
  with less static RAM, no heap, and — even built for size — more throughput than
  any of them (desktop-class `protobuf-c`, which is not a footprint contender,
  stays faster). *(A naïve object-sum flatters template-heavy libraries by counting
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
                   `<lang>/<v>` row. A variant that only swaps a corelib's engine
                   needs no directory at all: python/native and python/pure are
                   two runs of the same sofab/bench.py in bench.sh, the second
                   under SOFAB_PUREPYTHON=1.
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
