#!/usr/bin/env bash
# Java target: run every impl, print one BENCH line each to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

# Buffer the streaming impls render through, well below the ~434/494 B message so
# the drain path is exercised. ONE value for both sides of the streaming row: it
# compares codecs, not harness granularity (#108).
export STREAM_BUF_BYTES="${STREAM_BUF_BYTES:-64}"

# Portable JVM throughput tuning (applied to BOTH impls so the comparison stays
# fair). No CPU/ISA pinning. The 2M-iter loop already warms the tiered JIT; the
# goal is steady-state.
#   -XX:+UseParallelGC   throughput collector (beats the default G1 here).
#   -Xms/-Xmx 512m       fixed heap -> no resize pauses; 512 MB is safe anywhere.
#   -XX:+AlwaysPreTouch  commit+zero heap pages up front -> no page-fault stalls
#                        in the timed loop.
JAVA_TUNE="${JAVA_TUNE:--XX:+UseParallelGC -Xms512m -Xmx512m -XX:+AlwaysPreTouch}"

# Same jars, run once per impl: BENCH_IMPL selects the encode path inside each
# harness, so both impls of a pair come from one build and one set of JVM flags.
BENCH_IMPL=sofab           java $JAVA_TUNE -cp "$HERE/sofab/gen/target/harness.jar" message.Bench
BENCH_IMPL=protobuf        java $JAVA_TUNE -jar "$HERE/protobuf/target/harness.jar"
BENCH_IMPL=sofab-stream    java $JAVA_TUNE -cp "$HERE/sofab/gen/target/harness.jar" message.Bench
BENCH_IMPL=protobuf-stream java $JAVA_TUNE -jar "$HERE/protobuf/target/harness.jar"
