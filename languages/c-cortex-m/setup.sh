#!/usr/bin/env bash
# c-cortex-m target setup: nothing to build here — this target is FOOTPRINT-ONLY
# (cross-compiled, never executed). It reuses the generated code and vendored
# runtimes of the host c-embedded target; run that sibling setup if they are
# missing (idempotent). The cross toolchain itself is checked here so a missing
# compiler fails loudly at setup, not mid-measurement.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

command -v arm-none-eabi-gcc >/dev/null \
    || { echo "c-cortex-m: arm-none-eabi-gcc not installed (apt: gcc-arm-none-eabi)" >&2; exit 1; }

if [ ! -f "$ROOT/languages/c-embedded/sofab/gen/example.c" ] \
   || [ ! -f "$ROOT/languages/c-embedded/nanopb/gen/message.pb.c" ] \
   || [ ! -f "${NANOPB:-$ROOT/vendor/nanopb}/pb_encode.c" ]; then
    "$ROOT/languages/c-embedded/setup.sh"
fi

echo "c-cortex-m: setup OK" >&2
