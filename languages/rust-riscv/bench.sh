#!/usr/bin/env bash
# rust-riscv target: footprint-only — the binaries are cross-compiled for
# rv32imac and never executed, so there are no BENCH lines; the footprint
# probe emits one FOOTPRINT line per impl (sofab, micropb) on stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$HERE/footprint.sh"
