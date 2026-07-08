#!/usr/bin/env bash
# Zig target: run both release binaries, print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

"$HERE/sofab/gen/zig-out/bin/bench"
"$HERE/protobuf/zig-out/bin/bench"
