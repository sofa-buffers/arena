#!/usr/bin/env bash
# Rust target: run all three release binaries, print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

"$HERE/sofab/gen/target/release/bench"
cooldown_between_impls
"$HERE/sofab-heapless/gen/target/release/bench"
cooldown_between_impls
"$HERE/protobuf/target/release/bench"
