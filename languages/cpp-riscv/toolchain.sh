# Resolve the xpack riscv-none-elf toolchain (sourced by setup.sh/footprint.sh).
# Order: $RISCV_XPACK/bin > PATH > newest /opt/xpack-riscv-none-elf-gcc-*.
if [ -n "${RISCV_XPACK:-}" ] && [ -x "$RISCV_XPACK/bin/riscv-none-elf-g++" ]; then
    XPACK_BIN="$RISCV_XPACK/bin"
elif command -v riscv-none-elf-g++ >/dev/null 2>&1; then
    XPACK_BIN="$(dirname "$(command -v riscv-none-elf-g++)")"
else
    XPACK_BIN="$(ls -d /opt/xpack-riscv-none-elf-gcc-*/bin 2>/dev/null | sort -V | tail -1)"
fi
export XPACK_GXX="${XPACK_BIN:-/nonexistent}/riscv-none-elf-g++"
export XPACK_GCC="${XPACK_BIN:-/nonexistent}/riscv-none-elf-gcc"
