#!/usr/bin/env bash
# Java target: run both impls, print EXACTLY two BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

java -cp "$HERE/sofab/gen/target/harness.jar" message.Bench
java -jar "$HERE/protobuf/target/harness.jar"
