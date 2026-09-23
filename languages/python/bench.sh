#!/usr/bin/env bash
# Python target: run every impl (both corelib-py engines + protobuf),
# print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
ROOT="$(cd "$HERE/../.." && pwd)"
PY="${PYBIN:-$ROOT/tools/venv/bin/python}"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-200000}"

# corelib-py ships two engines behind one API: the compiled Cython accelerator
# (sofab._speedups) and the pure-Python fallback, byte-for-byte identical on the
# wire. Which one backs `sofab.Encoder`/`Decoder` is decided once per process, at
# `import sofab`, from SOFAB_PUREPYTHON — so each engine gets its own run of the
# SAME bench.py, with the same message, the same BENCH_ITERS and the same
# interpreter. The pair therefore isolates the engine and nothing else, and the
# pure row shows what the accelerator is actually worth (it is the slower of the
# two by ~7x — see README.md). Both runs are labelled, so this target has no plain
# `sofab` row: which engine ran is the point of the pair, not a footnote.
# BENCH_IMPL only labels the row; bench.py asserts the engine that actually
# resolved matches it.
PYTHONPATH="$ROOT/vendor/corelib-py/src" \
    BENCH_IMPL=sofab-native "$PY" "$HERE/sofab/bench.py"
cooldown_between_impls
PYTHONPATH="$ROOT/vendor/corelib-py/src" SOFAB_PUREPYTHON=1 \
    BENCH_IMPL=sofab-pure "$PY" "$HERE/sofab/bench.py"
cooldown_between_impls
"$PY" "$HERE/protobuf/bench.py"
