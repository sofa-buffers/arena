#!/usr/bin/env bash
# cpp-riscv target setup: nothing to build here — this target is FOOTPRINT-ONLY
# (cross-compiled for rv32imac, never executed). It reuses the generated code
# and vendored runtimes of the host cpp-embedded target; run that sibling setup
# if they are missing (idempotent).
#
# Toolchain: Ubuntu's riscv64-unknown-elf ships NO bare-metal libstdc++, so
# this target uses the xpack riscv-none-elf-gcc distribution (newlib +
# libstdc++, rv32imac/ilp32 is its default multilib). The devcontainer bakes it
# into /opt; outside the container set RISCV_XPACK or put riscv-none-elf-g++ on
# PATH. Checked here so a missing toolchain fails loudly at setup.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# shellcheck source=/dev/null
source "$HERE/toolchain.sh"   # resolves + exports XPACK_GXX / XPACK_GCC
[ -x "$XPACK_GXX" ] \
    || { echo "cpp-riscv: riscv-none-elf-g++ not found (xpack toolchain; see .devcontainer/Dockerfile)" >&2; exit 1; }
echo '#include <cstdint>' | "$XPACK_GXX" -march=rv32imac -mabi=ilp32 -std=c++20 -x c++ -fsyntax-only - \
    || { echo "cpp-riscv: xpack libstdc++ headers missing" >&2; exit 1; }

if [ ! -f "$ROOT/languages/cpp-embedded/sofab/gen/example.hpp" ] \
   || [ ! -f "$ROOT/languages/cpp-embedded/embeddedproto/gen/message.h" ] \
   || [ ! -f "${EP:-$ROOT/vendor/EmbeddedProto}/src/Fields.cpp" ]; then
    "$ROOT/languages/cpp-embedded/setup.sh"
fi

echo "cpp-riscv: setup OK" >&2
