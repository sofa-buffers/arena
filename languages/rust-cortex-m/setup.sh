#!/usr/bin/env bash
# rust-cortex-m target setup: nothing to build here — this target is
# FOOTPRINT-ONLY (cross-compiled, never executed). It builds the FFI wrapper
# crates of the host rust-embedded target (sofab-ffi / micropb-ffi) for
# thumbv7em-none-eabihf in footprint.sh; here we only make sure the toolchain
# and the sibling's generated crate exist so a missing prerequisite fails
# loudly at setup, not mid-measurement.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export PATH="/usr/local/cargo/bin:$HOME/.cargo/bin:$PATH"

command -v arm-none-eabi-gcc >/dev/null \
    || { echo "rust-cortex-m: arm-none-eabi-gcc not installed (apt: gcc-arm-none-eabi)" >&2; exit 1; }
command -v cargo >/dev/null \
    || { echo "rust-cortex-m: cargo not installed" >&2; exit 1; }
# Idempotent: instant no-op when the std lib for the target is already there.
rustup target add thumbv7em-none-eabihf >&2

if [ ! -f "$ROOT/languages/rust-embedded/sofab/gen/src/message.rs" ]; then
    "$ROOT/languages/rust-embedded/setup.sh"
fi

echo "rust-cortex-m: setup OK" >&2
