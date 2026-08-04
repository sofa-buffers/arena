#!/usr/bin/env bash
# C++ target: run every impl, print one BENCH line each to stdout.
#
# Order matters only for readability: the two one-shot impls that form the
# headline row first, then the #107 storage variant, then the #108 streaming pair
# (which the runner joins into its own cpp/stream row).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

"$HERE/sofab/bench"
"$HERE/sofab-heapfree/bench"
"$HERE/protobuf/bench"
"$HERE/sofab/bench-stream"
"$HERE/protobuf/bench-stream"
