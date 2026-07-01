#!/usr/bin/env bash
# C++ target: run both impls, print exactly two BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

"$HERE/sofab/bench"
"$HERE/protobuf/bench"
