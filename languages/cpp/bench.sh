#!/usr/bin/env bash
# C++ target: run all three impls, print exactly three BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

"$HERE/sofab/bench"
"$HERE/sofab-heapfree/bench"
"$HERE/protobuf/bench"
