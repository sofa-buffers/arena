#!/usr/bin/env bash
# Java target: run both impls, print EXACTLY two BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

# Same JVM flags for both impls; no CPU/ISA pinning, default GC. A fixed,
# pre-touched heap only keeps resize pauses and page faults out of the loop.
JAVA_TUNE="${JAVA_TUNE:--Xms512m -Xmx512m -XX:+AlwaysPreTouch}"

java $JAVA_TUNE -cp "$HERE/sofab/gen/target/harness.jar" bench.Bench
cooldown_between_impls
java $JAVA_TUNE -jar "$HERE/protobuf/target/harness.jar"
