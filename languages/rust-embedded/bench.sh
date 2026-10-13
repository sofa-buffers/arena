#!/usr/bin/env bash
# rust-embedded target: run both release bench binaries (2 BENCH lines) on stdout.
# No FOOTPRINT here: the codecs' footprint is the bare-metal --gc-sections link
# delta measured by the rust-cortex-m / rust-riscv siblings (via sofab-ffi /
# micropb-ffi); a host build would be dominated by std code.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

"$HERE/sofab/gen/target/release/bench"
cooldown_between_impls
"$HERE/micropb/target/release/bench"
