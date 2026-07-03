#!/usr/bin/env bash
# Bare-metal footprint probe: C codecs cross-compiled for ARM Cortex-M4.
#
# Prints ONE line per impl:
#   FOOTPRINT lang=c-cortex-m impl=<sofab|nanopb> text=<b> rodata=<b> data=<b> bss=<b>
#
# Methodology — LINK DELTA with --gc-sections (the fair firmware metric):
#   * The host c-embedded target sums codec OBJECT files, which counts every
#     function whether or not real firmware would keep it. Here each codec is
#     instead LINKED into a minimal bare-metal program with -Wl,--gc-sections,
#     and the reported figure is section(codec program) - section(empty baseline):
#     exactly the flash/RAM the codec adds to an application, including any libc
#     routines (memcpy, ...) only the codec pulls in.
#   * Target: cortex-m4 hard-float (thumb/v7e-m+fp), newlib-nano + nosys stubs,
#     -Os -DNDEBUG (release firmware build: asserts stripped) -ffunction-sections
#     -fdata-sections.
#   * The driver calls the real encode+decode entry points (through a volatile
#     sink so nothing is optimized away); its own buffers/state live in a custom
#     .harness section so driver data never counts toward the codec's .bss.
#   * The binaries are never executed — this target measures size only.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
NANOPB="${NANOPB:-$ROOT/vendor/nanopb}"
GEN_SOFAB="$ROOT/languages/c-embedded/sofab/gen"
GEN_NANOPB="$ROOT/languages/c-embedded/nanopb/gen"

CC=arm-none-eabi-gcc
CFLAGS="-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 \
        -Os -DNDEBUG -ffunction-sections -fdata-sections -std=c99"
LDFLAGS="--specs=nano.specs --specs=nosys.specs -Wl,--gc-sections"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
    printf 'FOOTPRINT lang=c-cortex-m impl=%s text=%s rodata=%s data=%s bss=%s\n' "$impl" "$t" "$r" "$d" "$b"
}

# --- empty baseline (CRT + libc startup only) ----------------------------------
cat > "$TMP/baseline.c" <<'EOF'
#include <stddef.h>
__attribute__((section(".harness"))) volatile size_t sink;
int main(void) { sink = 0; return 0; }
EOF
$CC $CFLAGS $LDFLAGS "$TMP/baseline.c" -o "$TMP/baseline.elf" >/dev/null

# --- sofab: generated object API + corelib-c-cpp codec --------------------------
cat > "$TMP/drv_sofab.c" <<'EOF'
#include "example.h"
#define HARNESS __attribute__((section(".harness")))
HARNESS static fullscale_example_t msg;
HARNESS static uint8_t buf[512];
HARNESS volatile size_t sink;
int main(void) {
    size_t used = 0;
    fullscale_example_encode(&msg, buf, sizeof buf, &used);
    fullscale_example_decode(&msg, buf, used);
    sink = used;
    return 0;
}
EOF
$CC $CFLAGS $LDFLAGS "$TMP/drv_sofab.c" \
    "$GEN_SOFAB"/*.c \
    "$CORELIB/src/object.c" "$CORELIB/src/ostream.c" "$CORELIB/src/istream.c" \
    -I"$CORELIB/src/include" -I"$GEN_SOFAB" -o "$TMP/sofab.elf" >/dev/null
emit_delta sofab "$TMP/sofab.elf" "$TMP/baseline.elf"

# --- nanopb: generated descriptors + nanopb runtime -----------------------------
cat > "$TMP/drv_nanopb.c" <<'EOF'
#include <pb_encode.h>
#include <pb_decode.h>
#include "message.pb.h"
#define HARNESS __attribute__((section(".harness")))
HARNESS static fullscale_FullScaleExample msg;
HARNESS static uint8_t buf[512];
HARNESS volatile size_t sink;
int main(void) {
    pb_ostream_t os = pb_ostream_from_buffer(buf, sizeof buf);
    pb_encode(&os, fullscale_FullScaleExample_fields, &msg);
    pb_istream_t is = pb_istream_from_buffer(buf, os.bytes_written);
    pb_decode(&is, fullscale_FullScaleExample_fields, &msg);
    sink = os.bytes_written;
    return 0;
}
EOF
$CC $CFLAGS $LDFLAGS "$TMP/drv_nanopb.c" \
    "$GEN_NANOPB/message.pb.c" \
    "$NANOPB/pb_encode.c" "$NANOPB/pb_decode.c" "$NANOPB/pb_common.c" \
    -I"$NANOPB" -I"$GEN_NANOPB" -o "$TMP/nanopb.elf" >/dev/null
emit_delta nanopb "$TMP/nanopb.elf" "$TMP/baseline.elf"
