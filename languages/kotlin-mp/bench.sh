#!/usr/bin/env bash
# Kotlin Multiplatform target: run both impls, print EXACTLY two BENCH lines to
# stdout. No Gradle here — setup.sh wrote each harness's runtime classpath out,
# so the timed process is a bare `java` with nothing of the build system in it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

# Same JVM flags for both impls (and as the java target); no CPU/ISA pinning,
# default GC. A fixed, pre-touched heap only keeps resize pauses and page
# faults out of the loop.
JAVA_TUNE="${JAVA_TUNE:--Xms512m -Xmx512m -XX:+AlwaysPreTouch}"

java $JAVA_TUNE -cp "$(cat "$HERE/sofab/build/bench-classpath.txt")"    bench.BenchKt
cooldown_between_impls
java $JAVA_TUNE -cp "$(cat "$HERE/protobuf/build/bench-classpath.txt")" bench.BenchKt
