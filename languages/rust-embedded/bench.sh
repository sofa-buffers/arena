#!/usr/bin/env bash
# rust-embedded target: run both release bench binaries (2 BENCH lines) on stdout.
#
# NOTE: FOOTPRINT is intentionally NOT emitted here. A host staticlib object-sum
# for Rust is dominated by std/panic/fmt code (both impls landed ~78-81k .text),
# so it is not a meaningful codec-footprint comparison. The fair metric is a
# bare-metal ARM --gc-sections build (parked); footprint.sh is kept for that.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

"$HERE/sofab/gen/target/release/bench"
"$HERE/micropb/target/release/bench"
