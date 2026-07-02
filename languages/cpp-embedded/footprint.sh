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
#                    (object.c/ostream.c/istream.c).
#   * embeddedproto codec = message.h instantiation + EmbeddedProto runtime
#                    sources (Fields.cpp/MessageInterface.cpp/ReadBufferSection.cpp).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
EP="${EP:-$ROOT/vendor/EmbeddedProto}"
COMMON="$ROOT/languages/common"

CFLAGS="-Os -ffunction-sections -fdata-sections"
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
// Force instantiation of the generated encode/decode codec surface.
std::vector<std::uint8_t> fp_encode(const Example &m) { return m.encode(); }
Example fp_decode(const std::uint8_t *d, std::size_t n) { return Example::decode(d, n); }
EOF
g++ $CFLAGS -std=c++20 -c "$TMP/drv_sofab.cpp" \
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
::EmbeddedProto::Error fp_decode(FullScaleExample &m, ::EmbeddedProto::ReadBufferInterface &b) { return m.deserialize(b); }
EOF
g++ $CFLAGS -std=c++17 -c "$TMP/drv_ep.cpp" \
    -I "$HERE/embeddedproto/gen" -I "$EP/src" -o "$TMP/drv_ep.o"
g++ $CFLAGS -std=c++17 -c \
    "$EP/src/Fields.cpp" "$EP/src/MessageInterface.cpp" "$EP/src/ReadBufferSection.cpp" \
    -I "$EP/src"
mv ./Fields.o ./MessageInterface.o ./ReadBufferSection.o "$TMP"/
emit embeddedproto "$(sum_sections "$TMP"/drv_ep.o "$TMP"/Fields.o "$TMP"/MessageInterface.o "$TMP"/ReadBufferSection.o)"
