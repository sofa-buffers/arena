#!/usr/bin/env bash
# Dart target: run both AOT-compiled native executables, print BENCH lines to
# stdout (logs -> stderr; the runner discovers impls from BENCH lines only).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

# No VM tuning knobs to export: both impls are AOT-compiled native executables
# (no JIT warm-up, no GC flags exposed the way `dart run` would need), so they
# already run on equal terms. Run sofab first.
"$HERE/sofab/gen/bin/bench"
cooldown_between_impls
"$HERE/protobuf/bench"
