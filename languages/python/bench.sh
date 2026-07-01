#!/usr/bin/env bash
# Python target: run both impls, print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PY="${PYBIN:-$ROOT/tools/venv/bin/python}"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-200000}"

PYTHONPATH="$ROOT/vendor/corelib-py/src" "$PY" "$HERE/sofab/bench.py"
"$PY" "$HERE/protobuf/bench.py"
