#!/usr/bin/env bash
# Kotlin Multiplatform target setup: publish corelib-kotlin-mp to the local maven
# repo, generate both impls' sources (sofabgen / the Wire compiler) and build the
# two harnesses. Idempotent; exits 0 on success.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="$ROOT/vendor/corelib-kotlin-mp"

# Gradle's Kotlin DSL compiler (embedded Kotlin, not the 2.4.x one it downloads
# for our sources) cannot parse the image's default JDK 25 version string and
# dies with `IllegalArgumentException: 25.0.3` before evaluating a single build
# file — so every Gradle invocation here runs on the JDK 21 the devcontainer
# installs alongside it. Only the BUILD is pinned to 21: bench.sh runs the
# harnesses on the default JVM, the same one the java target is measured on.
# `|| true`: with no match `ls` exits non-zero, and under `set -e` + `pipefail`
# that aborts the whole script AT THE ASSIGNMENT — silently, before the
# diagnostic below ever runs (the runner then logs an empty setup log and a bare
# exit 2). Let the assignment succeed empty and let the check do the talking.
GRADLE_JAVA_HOME="${GRADLE_JAVA_HOME:-$(ls -d /usr/lib/jvm/java-21-openjdk-* 2>/dev/null | head -1 || true)}"
# Test the emptiness SEPARATELY. With no match the variable is empty and
# "${GRADLE_JAVA_HOME:-}/bin/java" collapses to the literal `/bin/java`, which on
# Debian/Ubuntu is the default-JVM alternatives symlink and IS executable — so
# the check passed, `export JAVA_HOME=""` fell through, and Gradle ran on the
# image's JDK 25 and died with `IllegalArgumentException: 25.0.3` ten minutes
# later, after Kotlin/Native had downloaded its whole toolchain. Exactly the
# failure this guard exists to report immediately.
if [ -z "${GRADLE_JAVA_HOME:-}" ] || [ ! -x "$GRADLE_JAVA_HOME/bin/java" ]; then
    echo "kotlin-mp: no JDK <= 24 found for Gradle (looked for" \
         "/usr/lib/jvm/java-21-openjdk-*); install openjdk-21-jdk-headless as" \
         ".devcontainer/Dockerfile does, or set GRADLE_JAVA_HOME" >&2
    exit 1
fi
export JAVA_HOME="$GRADLE_JAVA_HOME"

# (1) Publish corelib-kotlin-mp to the local maven repo. Only the two
#     publications a JVM consumer resolves — the root Gradle-module metadata and
#     the jvm variant — so a run does not build the js/native legs the arena
#     never measures. The corelib's own wrapper drives it (it pins the Gradle
#     version the library is developed against).
VER="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$CORELIB/build.gradle.kts" | head -1)"
[ -n "$VER" ] || { echo "kotlin-mp: cannot read corelib-kotlin-mp version" >&2; exit 1; }
( cd "$CORELIB" && ./gradlew --quiet --console=plain \
    publishKotlinMultiplatformPublicationToMavenLocal publishJvmPublicationToMavenLocal )

# (2) sofab: generate the typed message sources.
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang kotlin \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >/dev/null

# `emit: project` is generated for the Json helper the driver fills from (see
# sofab/cfg.yaml), and brings along a single-target Kotlin/JVM scaffolding plus a
# conformance CLI. Drop both: this row builds its own Kotlin Multiplatform
# project, and Main.kt is the one generated file that is NOT platform-free
# (System.in/out, exitProcess), so it cannot live in commonMain. What stays under
# gen/ is exactly the commonMain codec.
rm -f "$HERE/sofab/gen/build.gradle.kts" "$HERE/sofab/gen/settings.gradle.kts" \
      "$HERE/sofab/gen/README.md" "$HERE/sofab/gen/src/main/kotlin/message/Main.kt"

# (3) protobuf: Square Wire's compiler CLI is this row's protoc — it turns the
#     .proto into Kotlin Multiplatform sources directly (no Java anywhere in the
#     chain). Its version is read off protobuf/build.gradle.kts so the generator
#     can never drift from the wire-runtime the harness links.
WIRE_VER="$(sed -n 's/.*com\.squareup\.wire:wire-runtime:\([^"]*\)".*/\1/p' \
    "$HERE/protobuf/build.gradle.kts" | head -1)"
[ -n "$WIRE_VER" ] || { echo "kotlin-mp: cannot read wire version" >&2; exit 1; }
WIRE_JAR="$ROOT/vendor/wire/wire-compiler-$WIRE_VER-jar-with-dependencies.jar"
if [ ! -f "$WIRE_JAR" ]; then
    mkdir -p "$ROOT/vendor/wire"
    echo "kotlin-mp: fetching wire-compiler $WIRE_VER" >&2
    curl -fsSL -o "$WIRE_JAR.tmp" \
        "https://repo1.maven.org/maven2/com/squareup/wire/wire-compiler/$WIRE_VER/wire-compiler-$WIRE_VER-jar-with-dependencies.jar"
    mv "$WIRE_JAR.tmp" "$WIRE_JAR"
fi
mkdir -p "$HERE/protobuf/gen/src/main/kotlin"
java -jar "$WIRE_JAR" --proto_path="$ROOT/schema" \
    --kotlin_out="$HERE/protobuf/gen/src/main/kotlin" message.proto >/dev/null

# (4) Build both harnesses in the one Gradle build that holds them, so they
#     cannot pick up different compiler settings (see build.gradle.kts), and
#     write out the runtime classpath bench.sh runs them from.
( cd "$HERE" && gradle --quiet --console=plain -Psofab.version="$VER" \
    :sofab:benchClasspath :protobuf:benchClasspath )

echo "kotlin-mp: setup OK (corelib-kotlin-mp $VER, wire $WIRE_VER)" >&2
