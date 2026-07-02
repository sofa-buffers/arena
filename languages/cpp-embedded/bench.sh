#!/usr/bin/env bash
# cpp-embedded target: run both benches (2 BENCH lines) then the object-sum
# footprint probe (2 FOOTPRINT lines) on stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

"$HERE/sofab/bench"
"$HERE/embeddedproto/bench"
"$HERE/footprint.sh"
