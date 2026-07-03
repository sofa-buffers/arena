#!/usr/bin/env bash
# cpp-cortex-m target setup: nothing to build here — this target is
# FOOTPRINT-ONLY (cross-compiled, never executed). It reuses the generated code
# and vendored runtimes of the host cpp-embedded target; run that sibling setup
# if they are missing (idempotent). The cross toolchain (incl. the newlib
# libstdc++ multilib) is checked here so a missing compiler fails loudly at
# setup, not mid-measurement.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

command -v arm-none-eabi-g++ >/dev/null \
    || { echo "cpp-cortex-m: arm-none-eabi-g++ not installed (apt: gcc-arm-none-eabi + libstdc++-arm-none-eabi-newlib)" >&2; exit 1; }
echo '#include <cstdint>' | arm-none-eabi-g++ -mcpu=cortex-m4 -mthumb -std=c++20 -x c++ -fsyntax-only - \
    || { echo "cpp-cortex-m: arm-none-eabi libstdc++ headers missing (apt: libstdc++-arm-none-eabi-newlib)" >&2; exit 1; }

if [ ! -f "$ROOT/languages/cpp-embedded/sofab/gen/example.hpp" ] \
   || [ ! -f "$ROOT/languages/cpp-embedded/embeddedproto/gen/message.h" ] \
   || [ ! -f "${EP:-$ROOT/vendor/EmbeddedProto}/src/Fields.cpp" ]; then
    "$ROOT/languages/cpp-embedded/setup.sh"
fi

echo "cpp-cortex-m: setup OK" >&2
