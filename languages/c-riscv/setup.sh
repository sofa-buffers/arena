#!/usr/bin/env bash
# c-riscv target setup: nothing to build here — this target is FOOTPRINT-ONLY
# (cross-compiled for rv32imac, never executed). It reuses the generated code
# and vendored runtimes of the host c-embedded target; run that sibling setup
# if they are missing (idempotent). The cross toolchain is checked here so a
# missing compiler fails loudly at setup, not mid-measurement.
#
# C only here: Ubuntu's riscv64-unknown-elf toolchain ships picolibc but NO
# bare-metal libstdc++ (no <cstdint>/<string> for rv32). The cpp-riscv sibling
# covers C++ via the xpack riscv-none-elf toolchain instead.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

command -v riscv64-unknown-elf-gcc >/dev/null \
    || { echo "c-riscv: riscv64-unknown-elf-gcc not installed (apt: gcc-riscv64-unknown-elf + picolibc-riscv64-unknown-elf)" >&2; exit 1; }

if [ ! -f "$ROOT/languages/c-embedded/sofab/gen/example.c" ] \
   || [ ! -f "$ROOT/languages/c-embedded/nanopb/gen/message.pb.c" ] \
   || [ ! -f "${NANOPB:-$ROOT/vendor/nanopb}/pb_encode.c" ]; then
    "$ROOT/languages/c-embedded/setup.sh"
fi

echo "c-riscv: setup OK" >&2
