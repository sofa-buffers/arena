#!/usr/bin/env bash
# rust-riscv target setup: nothing to build here — this target is
# FOOTPRINT-ONLY (cross-compiled for rv32imac, never executed). It builds the
# FFI wrapper crates of the host rust-embedded target (sofab-ffi / micropb-ffi)
# for riscv32imac-unknown-none-elf in footprint.sh; here we only make sure the
# toolchain and the sibling's generated crate exist so a missing prerequisite
# fails loudly at setup, not mid-measurement.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export PATH="/usr/local/cargo/bin:$HOME/.cargo/bin:$PATH"

command -v riscv64-unknown-elf-gcc >/dev/null \
    || { echo "rust-riscv: riscv64-unknown-elf-gcc not installed (apt: gcc-riscv64-unknown-elf + picolibc-riscv64-unknown-elf)" >&2; exit 1; }
command -v cargo >/dev/null \
    || { echo "rust-riscv: cargo not installed" >&2; exit 1; }
# Idempotent: instant no-op when the std lib for the target is already there.
rustup target add riscv32imac-unknown-none-elf >&2

if [ ! -f "$ROOT/languages/rust-embedded/sofab/gen/src/message.rs" ]; then
    "$ROOT/languages/rust-embedded/setup.sh"
fi

echo "rust-riscv: setup OK" >&2
