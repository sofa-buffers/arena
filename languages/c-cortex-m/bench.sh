#!/usr/bin/env bash
# c-cortex-m target: footprint-only — the binaries are cross-compiled for a
# Cortex-M4 and never executed, so there are no BENCH lines; the footprint
# probe emits one FOOTPRINT line per impl (sofab, nanopb) on stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$HERE/footprint.sh"
