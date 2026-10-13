#!/usr/bin/env bash
# Footprint probe for the three C serialization codecs.
#
# Prints ONE line per impl:
#   FOOTPRINT lang=c-embedded impl=<sofab|nanopb|protobuf-c> text=<b> rodata=<b> data=<b> bss=<b>
#
# Methodology: object-sum of the codec's .text/.rodata/.data/.bss via `size -A`
# (generated code + runtime; bench.c and sha256 are harness, not codec). Every
# function in those objects counts, used or not; the bare-metal siblings
# (c-cortex-m, c-riscv) measure the --gc-sections link delta instead.
#   * sofab / nanopb: compiled here from source with -Os -ffunction-sections
#     -fdata-sections -std=c99.
#   * protobuf-c: no runtime source is available, so its figure is the generated
#     code (same flags) plus the WHOLE distro libprotobuf-c.a as shipped (built
#     with the distro's flags, not -Os), so this row is not flag-identical.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
NANOPB="${NANOPB:-$ROOT/vendor/nanopb}"
COMMON="$ROOT/languages/common"
BENCHINC="$HERE"   # bench.h timing harness (lives with this target)

CFLAGS="-Os -DNDEBUG -ffunction-sections -fdata-sections -std=c99"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# sum_sections <obj-or-bin> ... -> "text rodata data bss"
sum_sections() {
    size -A "$@" | awk '
        $1 ~ /^\.text/   { text += $2 }
        $1 ~ /^\.rodata/ { rod  += $2 }
        $1 ~ /^\.data/   { dat  += $2 }
        $1 ~ /^\.bss/    { bss  += $2 }
        END { printf "%d %d %d %d\n", text, rod, dat, bss }'
}

emit() { # impl "text rodata data bss"
    local impl="$1"
    read -r t r d b <<<"$2"
    printf 'FOOTPRINT lang=c-embedded impl=%s text=%s rodata=%s data=%s bss=%s\n' "$impl" "$t" "$r" "$d" "$b"
}

# --- sofab: object-sum of generated code + corelib codec ----------------------
gcc $CFLAGS -c \
    "$HERE"/sofab/gen/*.c \
    "$CORELIB/src/object.c" "$CORELIB/src/ostream.c" "$CORELIB/src/istream.c" \
    -I"$CORELIB/src/include" -I"$HERE/sofab/gen" -I"$COMMON" -I"$BENCHINC"
mv ./*.o "$TMP"/ 2>/dev/null || true
SOFAB_OBJS=("$TMP"/example.o "$TMP"/object.o "$TMP"/ostream.o "$TMP"/istream.o)
emit sofab "$(sum_sections "${SOFAB_OBJS[@]}")"
rm -f "$TMP"/*.o

# --- nanopb: object-sum of generated code + nanopb runtime --------------------
gcc $CFLAGS -c \
    "$HERE/nanopb/gen/message.pb.c" \
    "$NANOPB/pb_encode.c" "$NANOPB/pb_decode.c" "$NANOPB/pb_common.c" \
    -I"$NANOPB" -I"$HERE/nanopb/gen"
mv ./*.o "$TMP"/ 2>/dev/null || true
NANOPB_OBJS=("$TMP"/message.pb.o "$TMP"/pb_encode.o "$TMP"/pb_decode.o "$TMP"/pb_common.o)
emit nanopb "$(sum_sections "${NANOPB_OBJS[@]}")"
rm -f "$TMP"/*.o

# --- protobuf-c: generated code + whole prebuilt runtime archive ---------------
PBC_A="$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu -name 'libprotobuf-c.a' 2>/dev/null | head -1)"
gcc $CFLAGS -c "$HERE/protobuf/gen/message.pb-c.c" -I"$HERE/protobuf/gen"
mv ./*.o "$TMP"/ 2>/dev/null || true
if [ -n "$PBC_A" ]; then
    emit protobuf-c "$(sum_sections "$TMP"/message.pb-c.o "$PBC_A")"
else
    echo "footprint: libprotobuf-c.a not found — protobuf-c shows generated code only" >&2
    emit protobuf-c "$(sum_sections "$TMP"/message.pb-c.o)"
fi
rm -f "$TMP"/*.o
