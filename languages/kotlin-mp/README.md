# `kotlin-mp` — Kotlin Multiplatform (maxspeed)

SofaBuffers' [`corelib-kotlin-mp`](https://github.com/sofa-buffers/corelib-kotlin-mp)
against [**Square Wire**](https://github.com/square/wire), measured on the JVM.

## Why Wire is the opponent

The row's rule is that **both** codecs must be Kotlin Multiplatform, so the
baseline had to be a protobuf implementation that emits Kotlin *directly* —
`protoc --kotlin_out` was disqualified: it generates a DSL layer whose messages
are still protobuf-**java** classes, which is a JVM library wearing Kotlin
syntax, not a KMP codec.

Wire qualifies on both halves:

- its compiler emits Kotlin whose only imports are `kotlin.*`, `okio` and
  `com.squareup.wire` — the JVM-specific pieces (`JvmField`) come through Wire's
  own `expect`/`actual` shims, so the generated messages compile in `commonMain`;
- `wire-runtime` is published as a KMP library (jvm / js / native), like
  `corelib-kotlin-mp` itself.

Both codecs therefore live in `commonMain` here, and only the benchmark drivers
(file I/O, SHA-256, `String.format`) sit in `jvmMain` — the platform the arena
measures.

## Layout

```
build.gradle.kts      the shared half of BOTH impls' build: KMP plugin, JVM
                      target, toolchain, compiler flags, the benchClasspath task
settings.gradle.kts   one build, two subprojects (:sofab, :protobuf)
sofab/
  cfg.yaml            sofabgen config (emit: project — for the Json helper)
  gen/                generated commonMain codec (Main.kt + the single-target
                      scaffolding are pruned by setup.sh; see below)
  src/jvmMain/        the driver, package `message`
protobuf/
  build.gradle.kts    the Wire version — single source of truth (setup.sh reads
                      it back out to fetch the matching compiler CLI)
  gen/                Wire-generated commonMain codec
  src/jvmMain/        the driver, package `bench`
```

The two impls share one Gradle build on purpose: the arena's "identical
optimization per row" rule is then structural rather than a promise — there is
no second build file that could drift.

## Two JDKs, and why

Gradle 8.14.5's **embedded** Kotlin DSL compiler cannot parse the devcontainer's
default JDK version string (`25.0.3`) and aborts before it evaluates a build
file, so `setup.sh` pins **every Gradle invocation to the image's build-only
JDK 21** (override with `GRADLE_JAVA_HOME`). That is a build-time detail only:
`bench.sh` runs both harnesses on the **default JVM**, the same one the `java`
target is measured on, through a bare `java -cp …` — no Gradle daemon anywhere
near the timed loop.

## Pruned generated files

`sofab/cfg.yaml` asks for `emit: project` because the sources-only mode does not
emit the `Json` helper the driver fills the message from. The project mode also
writes a single-target Kotlin/JVM scaffolding and a conformance CLI; `setup.sh`
deletes both. `Main.kt` in particular is the one generated file that is *not*
platform-free (`System.in`/`System.out`, `exitProcess`), so it could not live in
`commonMain` anyway. What stays under `gen/` is exactly the commonMain codec.

## Timing

`System.nanoTime()` around the chained `encode(decode(blob))` loop, identical for
both impls — the same helper the `java` target uses, so the two JVM rows are
measured the same way (docs/BENCH.md allows a per-target timing helper as long as
every impl in the target shares it).
