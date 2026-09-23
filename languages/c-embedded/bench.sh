#!/usr/bin/env bash
# C target: run all three impls (sofab, protobuf-c, nanopb) => three BENCH lines,
# then the footprint probe => three FOOTPRINT lines. All on stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
export BENCH_ITERS="${BENCH_ITERS:-500000}"

"$HERE/sofab/bench"
cooldown_between_impls
"$HERE/protobuf/bench"
cooldown_between_impls
"$HERE/nanopb/bench"

"$HERE/footprint.sh"
