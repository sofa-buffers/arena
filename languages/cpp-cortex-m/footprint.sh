#!/usr/bin/env bash
# Bare-metal footprint probe: C++ codecs cross-compiled for ARM Cortex-M4.
#
# Prints ONE line per impl:
#   FOOTPRINT lang=cpp-cortex-m impl=<sofab|embeddedproto> text=<b> rodata=<b> data=<b> bss=<b>
#
# Methodology — LINK DELTA with --gc-sections (same as c-cortex-m):
#   * Each codec is linked into a minimal bare-metal program with
#     -Wl,--gc-sections; the figure is section(codec program) - section(empty
#     baseline): the flash/RAM the codec actually adds to an application.
#   * Target: cortex-m4 hard-float (thumb/v7e-m+fp), newlib-nano + nosys stubs,
#     -Os -flto -DNDEBUG -fno-exceptions -fno-rtti (typical release firmware C++).
#   * sofab uses the fixed-capacity profile's heap-free entry points
#     (encodeTo(buf, cap, used) / try_decode(buf, len, dst)) — NOT the
#     std::vector-returning encode(), which would drag the allocator into the
#     delta. EmbeddedProto uses serialize()/clear()+deserialize() on its
#     fixed-size buffers. Buffers are sized with each API's own worst-case
#     bound (Example::_maxSize / FullScaleExample::max_serialized_size()) and
#     every returned verdict is folded into the volatile sink.
#   * Driver state lives in a custom .harness section so it never counts
#     toward the codec's .bss. The binaries are never executed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
EP="${EP:-$ROOT/vendor/EmbeddedProto}"
GEN_SOFAB="$ROOT/languages/cpp-embedded/sofab/gen"
GEN_EP="$ROOT/languages/cpp-embedded/embeddedproto/gen"

CC=arm-none-eabi-gcc
CXX=arm-none-eabi-g++
ARCH="-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16"
CFLAGS="$ARCH -Os -flto -DNDEBUG -ffunction-sections -fdata-sections"
# Embedded C++ release flags. Beyond -fno-exceptions/-fno-rtti: -fno-threadsafe-statics
# drops the __cxa_guard_* guard on function-local statics; -fno-use-cxa-atexit
# drops the __cxa_atexit/__dso_handle dtor registration for global objects — dead
# weight in firmware that never calls exit(); -fno-unwind-tables/
# -fno-asynchronous-unwind-tables strip .ARM.exidx/.eh_frame. Same set as
# languages/cpp-embedded/footprint.sh plus -fno-use-cxa-atexit, which only
# matters once global objects are linked.
CXXFLAGS="$CFLAGS -fno-exceptions -fno-rtti -fno-threadsafe-statics \
          -fno-use-cxa-atexit -fno-unwind-tables -fno-asynchronous-unwind-tables"
LDFLAGS="--specs=nano.specs --specs=nosys.specs -Wl,--gc-sections"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# sum_sections <elf> -> "text rodata data bss"
sum_sections() {
    # bss from symbol sizes, not the section size: the section also holds the
    # linker's alignment fill, which moves with the driver's .harness layout.
    local bss
    bss="$("${CC%gcc}nm" -f sysv -t d "$1" | awk -F'|' '$7 ~ /^\.bss/ { s += $5 } END { print s + 0 }')"
    size -A "$1" | awk -v bss="$bss" '
        $1 ~ /^\.text/   { text += $2 }
        $1 ~ /^\.rodata/ { rod  += $2 }
        $1 ~ /^\.data/   { dat  += $2 }
        END { printf "%d %d %d %d\n", text, rod, dat, bss }'
}

emit_delta() { # <impl> <codec-elf> <baseline-elf>
    local impl="$1" t r d b t0 r0 d0 b0
    read -r t r d b     <<<"$(sum_sections "$2")"
    read -r t0 r0 d0 b0 <<<"$(sum_sections "$3")"
    t=$((t-t0)); r=$((r-r0)); d=$((d-d0)); b=$((b-b0))
    # alignment can make a section delta marginally negative; clamp to 0
    [ "$t" -lt 0 ] && t=0; [ "$r" -lt 0 ] && r=0; [ "$d" -lt 0 ] && d=0; [ "$b" -lt 0 ] && b=0
    printf 'FOOTPRINT lang=cpp-cortex-m impl=%s text=%s rodata=%s data=%s bss=%s\n' "$impl" "$t" "$r" "$d" "$b"
}

# --- empty baseline (CRT + libc startup only, linked as C++) --------------------
cat > "$TMP/baseline.cpp" <<'EOF'
#include <cstddef>
__attribute__((section(".harness"))) volatile std::size_t sink;
int main() { sink = 0; return 0; }
EOF
$CXX $CXXFLAGS -std=c++20 $LDFLAGS "$TMP/baseline.cpp" -o "$TMP/baseline.elf" >/dev/null

# --- sofab: generated C++ wrapper + corelib-c-cpp codec (compiled as C) ---------
cat > "$TMP/drv_sofab.cpp" <<'EOF'
#include "example.hpp"
using fullscale::Example;
#define HARNESS __attribute__((section(".harness")))
HARNESS static Example msg;
HARNESS static Example dec;
HARNESS static std::uint8_t buf[Example::_maxSize];
HARNESS volatile std::size_t sink;
int main() {
    std::size_t n = 0;
    sofab::Error e = msg.encodeTo(buf, sizeof buf, n);
    // try_decode resets `dec` and decodes into it in place (IStreamInto),
    // returning the verdict — the counterpart of embeddedproto's clear() +
    // deserialize().
    bool ok = Example::try_decode(buf, n, dec).ok();
    sink = n + (ok ? 0u : 1u) + (e == sofab::Error::None ? 0u : 2u);
    return 0;
}
EOF
( cd "$TMP" && $CC $CFLAGS -std=c99 -c \
    "$CORELIB/src/object.c" "$CORELIB/src/ostream.c" "$CORELIB/src/istream.c" \
    -I"$CORELIB/src/include" )
$CXX $CXXFLAGS -std=c++20 $LDFLAGS "$TMP/drv_sofab.cpp" \
    "$TMP/object.o" "$TMP/ostream.o" "$TMP/istream.o" \
    -I"$GEN_SOFAB" -I"$CORELIB/src/include" -o "$TMP/sofab.elf" >/dev/null
emit_delta sofab "$TMP/sofab.elf" "$TMP/baseline.elf"

# --- embeddedproto: generated header + EmbeddedProto runtime --------------------
cat > "$TMP/drv_ep.cpp" <<'EOF'
#include "message.h"
#include "WriteBufferFixedSize.h"
#include "ReadBufferFixedSize.h"
using fullscale::FullScaleExample;
#define HARNESS __attribute__((section(".harness")))
HARNESS static FullScaleExample msg;
HARNESS static FullScaleExample dec;
constexpr auto BUFSZ = FullScaleExample::max_serialized_size();
HARNESS static ::EmbeddedProto::WriteBufferFixedSize<BUFSZ> wbuf;
HARNESS static ::EmbeddedProto::ReadBufferFixedSize<BUFSZ> rbuf;
HARNESS volatile std::size_t sink;
int main() {
    auto e1 = msg.serialize(wbuf);
    // deserialize() decodes INTO the message without resetting it, so the
    // reused `dec` is cleared first.
    dec.clear();
    auto e2 = dec.deserialize(rbuf);
    sink = wbuf.get_size() + (e2 == ::EmbeddedProto::Error::NO_ERRORS ? 0u : 1u)
         + (e1 == ::EmbeddedProto::Error::NO_ERRORS ? 0u : 2u);
    return 0;
}
EOF
$CXX $CXXFLAGS -std=c++20 $LDFLAGS "$TMP/drv_ep.cpp" \
    "$EP/src/Fields.cpp" "$EP/src/MessageInterface.cpp" "$EP/src/ReadBufferSection.cpp" \
    -I"$GEN_EP" -I"$EP/src" -o "$TMP/ep.elf" >/dev/null
emit_delta embeddedproto "$TMP/ep.elf" "$TMP/baseline.elf"
