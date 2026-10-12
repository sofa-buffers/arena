#!/usr/bin/env bash
# Footprint probe for the two cpp-embedded serialization codecs.
#
# Prints ONE line per impl:
#   FOOTPRINT lang=cpp-embedded impl=<sofab|embeddedproto> text=<b> rodata=<b> data=<b> bss=<b>
#
# Methodology (kept consistent with languages/c/footprint.sh):
#   * Both codecs are C++ SOURCE libraries, so each is measured as an OBJECT SUM:
#     compile the codec translation units with -Os -ffunction-sections
#     -fdata-sections and sum the .text/.rodata/.data/.bss sections of the codec
#     object files via `size -A` (SysV). No libc, no linking.
#   * Neither codec exposes a standalone codec .o: the sofab wrapper (example.hpp)
#     and the EmbeddedProto generated types (message.h) are header/template code
#     that only emits machine code when instantiated. A tiny driver TU therefore
#     instantiates the encode/decode entry points; it is the codec surface (the
#     analogue of the C target's generated example.o), NOT harness. bench.cpp and
#     sha256 are excluded, exactly as in the C target.
#   * sofab codec  = example.hpp instantiation + corelib-c-cpp C sources
#                    (object.c/ostream.c/istream.c), instantiated through the
#                    heap-free encodeTo/try_decode entry points (see the driver
#                    below) — never the std::vector-returning encode().
#   * embeddedproto codec = message.h instantiation + EmbeddedProto runtime
#                    sources (Fields.cpp/MessageInterface.cpp/ReadBufferSection.cpp).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
EP="${EP:-$ROOT/vendor/EmbeddedProto}"
COMMON="$ROOT/languages/common"

CFLAGS="-Os -ffunction-sections -fdata-sections"
# Embedded C++ footprint flags: no exceptions / RTTI / unwind tables. These strip
# the exception machinery (.eh_frame/.gcc_except_table), typeinfo (.rodata) and
# static-init guards (.data) that no real firmware build carries — how both
# EmbeddedProto and the corelib C++ wrapper are meant to be compiled. C++-only, so
# they are appended to the g++ invocations, NOT to the shared CFLAGS used by gcc.
CXXEMB="-fno-exceptions -fno-rtti -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-threadsafe-statics"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# sum_sections <obj> ... -> "text rodata data bss"
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
    printf 'FOOTPRINT lang=cpp-embedded impl=%s text=%s rodata=%s data=%s bss=%s\n' "$impl" "$t" "$r" "$d" "$b"
}

# --- sofab: object-sum of example.hpp instantiation + corelib-c-cpp codec ------
cat > "$TMP/drv_sofab.cpp" <<'EOF'
#include "example.hpp"
using fullscale::Example;
// Force instantiation of the generated codec surface through the HEAP-FREE entry
// points — encodeTo(buf, cap) into caller storage and try_decode(data, len, out)
// into a caller-owned destination, both of which report their verdict. The
// allocating conveniences encode()/decode() would drag std::vector and the
// allocator into an embedded-league number, which is the same reason
// languages/cpp-cortex-m/footprint.sh links encodeTo; embeddedproto below is
// measured through its own buffer-interface serialize/deserialize pair, so this
// keeps the two surfaces like-for-like.
std::size_t fp_encode(const Example &m, std::uint8_t *dst, std::size_t cap) { return m.encodeTo(dst, cap); }
bool fp_decode(const std::uint8_t *d, std::size_t n, Example &out) { return Example::try_decode(d, n, out).ok(); }
EOF
g++ $CFLAGS $CXXEMB -std=c++20 -c "$TMP/drv_sofab.cpp" \
    -I "$HERE/sofab/gen" -I "$CORELIB/src/include" -o "$TMP/drv_sofab.o"
gcc $CFLAGS -std=c99 -c \
    "$CORELIB/src/object.c" "$CORELIB/src/ostream.c" "$CORELIB/src/istream.c" \
    -I "$CORELIB/src/include"
mv ./object.o ./ostream.o ./istream.o "$TMP"/
emit sofab "$(sum_sections "$TMP"/drv_sofab.o "$TMP"/object.o "$TMP"/ostream.o "$TMP"/istream.o)"

# --- embeddedproto: object-sum of message.h instantiation + EP runtime --------
cat > "$TMP/drv_ep.cpp" <<'EOF'
#include "message.h"
#include "WriteBufferFixedSize.h"
#include "ReadBufferFixedSize.h"
using fullscale::FullScaleExample;
// Force instantiation of the generated serialize/deserialize codec surface.
::EmbeddedProto::Error fp_encode(const FullScaleExample &m, ::EmbeddedProto::WriteBufferInterface &b) { return m.serialize(b); }
// clear() before deserialize(): EmbeddedProto decodes INTO the message without
// resetting it, so a reused destination needs this — the same work sofab's
// try_decode does internally, which is what keeps the two surfaces comparable.
::EmbeddedProto::Error fp_decode(FullScaleExample &m, ::EmbeddedProto::ReadBufferInterface &b) { m.clear(); return m.deserialize(b); }
EOF
g++ $CFLAGS $CXXEMB -std=c++17 -c "$TMP/drv_ep.cpp" \
    -I "$HERE/embeddedproto/gen" -I "$EP/src" -o "$TMP/drv_ep.o"
g++ $CFLAGS $CXXEMB -std=c++17 -c \
    "$EP/src/Fields.cpp" "$EP/src/MessageInterface.cpp" "$EP/src/ReadBufferSection.cpp" \
    -I "$EP/src"
mv ./Fields.o ./MessageInterface.o ./ReadBufferSection.o "$TMP"/
emit embeddedproto "$(sum_sections "$TMP"/drv_ep.o "$TMP"/Fields.o "$TMP"/MessageInterface.o "$TMP"/ReadBufferSection.o)"
