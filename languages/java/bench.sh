#!/usr/bin/env bash
# Java target: run both impls, print EXACTLY two BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

# Portable JVM throughput tuning (applied to BOTH impls so the comparison stays
# fair). No CPU/ISA pinning. The 2M-iter loop already warms the tiered JIT; the
# goal is steady-state.
#   -XX:+UseParallelGC   throughput collector (beats the default G1 here).
#   -Xms/-Xmx 512m       fixed heap -> no resize pauses; 512 MB is safe anywhere.
#   -XX:+AlwaysPreTouch  commit+zero heap pages up front -> no page-fault stalls
#                        in the timed loop.
JAVA_TUNE="${JAVA_TUNE:--XX:+UseParallelGC -Xms512m -Xmx512m -XX:+AlwaysPreTouch}"

java $JAVA_TUNE -cp "$HERE/sofab/gen/target/harness.jar" message.Bench
java $JAVA_TUNE -jar "$HERE/protobuf/target/harness.jar"
