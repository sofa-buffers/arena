#!/usr/bin/env bash
# Rust target: run both release binaries, print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

"$HERE/sofab/gen/target/release/bench"
"$HERE/protobuf/target/release/bench"
