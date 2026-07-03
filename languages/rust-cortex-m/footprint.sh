#!/usr/bin/env bash
# Bare-metal footprint probe: Rust codecs cross-compiled for ARM Cortex-M4.
#
# Prints ONE line per impl:
#   FOOTPRINT lang=rust-cortex-m impl=<sofab|micropb> text=<b> rodata=<b> data=<b> bss=<b>
#
# Methodology — LINK DELTA with --gc-sections (same as c-cortex-m):
#   * Each codec is a genuinely #![no_std], heap-free Rust staticlib: the
#     sofabgen-generated crate (corelib: rs-no-std, --no-default-features,
#     sofabgen >= 0.9.0) and the micropb-generated module, each wrapped by a
#     tiny extern "C" FFI crate under languages/rust-embedded/ (sofab-ffi /
#     micropb-ffi; opt-level=z, LTO, panic=abort).
#   * The staticlib is linked into the SAME minimal bare-metal C program /
#     empty baseline the C targets use (newlib-nano + nosys, -Os -DNDEBUG,
#     -Wl,--gc-sections); the figure is section(codec program) - section(empty
#     baseline). thumbv7em-none-eabihf is hard-float — the C driver must be
#     compiled -mfloat-abi=hard to match.
#   * The FFI wrapper black_boxes the message so LTO cannot const-fold the
#     encode of a known-default value; driver buffers live in a custom
#     .harness section so they never count toward the codec's .bss.
#   * The binaries are never executed — this target measures size only.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
RSEMB="$ROOT/languages/rust-embedded"
RUST_TARGET=thumbv7em-none-eabihf

export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export PATH="/usr/local/cargo/bin:$HOME/.cargo/bin:$PATH"

CC=arm-none-eabi-gcc
CFLAGS="-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 \
        -Os -DNDEBUG -ffunction-sections -fdata-sections -std=c99"
LDFLAGS="--specs=nano.specs --specs=nosys.specs -Wl,--gc-sections"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- build both no_std staticlibs for the ISA -----------------------------------
( cd "$RSEMB/sofab-ffi"   && cargo build --release --target "$RUST_TARGET" >&2 )
( cd "$RSEMB/micropb-ffi" && cargo build --release --target "$RUST_TARGET" >&2 )
SOFAB_A="$RSEMB/sofab-ffi/target/$RUST_TARGET/release/libsofab_ffi.a"
MICROPB_A="$RSEMB/micropb-ffi/target/$RUST_TARGET/release/libmicropb_ffi.a"

# sum_sections <elf> -> "text rodata data bss"
sum_sections() {
    size -A "$1" | awk '
        $1 ~ /^\.text/   { text += $2 }
        $1 ~ /^\.rodata/ { rod  += $2 }
        $1 ~ /^\.data/   { dat  += $2 }
        $1 ~ /^\.bss/    { bss  += $2 }
        END { printf "%d %d %d %d\n", text, rod, dat, bss }'
}

emit_delta() { # <impl> <codec-elf> <baseline-elf>
    local impl="$1" t r d b t0 r0 d0 b0
    read -r t r d b     <<<"$(sum_sections "$2")"
    read -r t0 r0 d0 b0 <<<"$(sum_sections "$3")"
    t=$((t-t0)); r=$((r-r0)); d=$((d-d0)); b=$((b-b0))
    # alignment can make a section delta marginally negative; clamp to 0
    [ "$t" -lt 0 ] && t=0; [ "$r" -lt 0 ] && r=0; [ "$d" -lt 0 ] && d=0; [ "$b" -lt 0 ] && b=0
    printf 'FOOTPRINT lang=rust-cortex-m impl=%s text=%s rodata=%s data=%s bss=%s\n' "$impl" "$t" "$r" "$d" "$b"
}

# --- empty baseline (CRT + libc startup only) ----------------------------------
cat > "$TMP/baseline.c" <<'EOF'
#include <stddef.h>
__attribute__((section(".harness"))) volatile size_t sink;
int main(void) { sink = 0; return 0; }
EOF
$CC $CFLAGS $LDFLAGS "$TMP/baseline.c" -o "$TMP/baseline.elf" >/dev/null

# --- sofab: generated no_std crate + corelib-rs-no-std, via sofab-ffi -----------
cat > "$TMP/drv_sofab.c" <<'EOF'
#include <stddef.h>
#include <stdint.h>
extern size_t sofab_roundtrip(uint8_t *buf, size_t cap);
#define HARNESS __attribute__((section(".harness")))
HARNESS static uint8_t buf[1024];
HARNESS volatile size_t sink;
int main(void) { sink = sofab_roundtrip(buf, sizeof buf); return 0; }
EOF
$CC $CFLAGS $LDFLAGS "$TMP/drv_sofab.c" "$SOFAB_A" -o "$TMP/sofab.elf" >/dev/null
emit_delta sofab "$TMP/sofab.elf" "$TMP/baseline.elf"

# --- micropb: generated no_std module + micropb runtime, via micropb-ffi --------
cat > "$TMP/drv_micropb.c" <<'EOF'
#include <stddef.h>
#include <stdint.h>
extern size_t micropb_roundtrip(uint8_t *out, size_t cap);
#define HARNESS __attribute__((section(".harness")))
HARNESS static uint8_t buf[1024];
HARNESS volatile size_t sink;
int main(void) { sink = micropb_roundtrip(buf, sizeof buf); return 0; }
EOF
$CC $CFLAGS $LDFLAGS "$TMP/drv_micropb.c" "$MICROPB_A" -o "$TMP/micropb.elf" >/dev/null
emit_delta micropb "$TMP/micropb.elf" "$TMP/baseline.elf"
