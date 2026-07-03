#!/usr/bin/env bash
# Bare-metal footprint probe: C++ codecs cross-compiled for RISC-V rv32imac.
#
# Prints ONE line per impl:
#   FOOTPRINT lang=cpp-riscv impl=<sofab|embeddedproto> text=<b> rodata=<b> data=<b> bss=<b>
#
# Methodology — LINK DELTA with --gc-sections (same as cpp-cortex-m, which has
# the full description): each codec linked into a minimal bare-metal program;
# figure = section(codec program) - section(empty baseline).
#   * Toolchain: xpack riscv-none-elf-gcc (Ubuntu ships no bare-metal libstdc++
#     for RISC-V). newlib-nano + nosys, rv32imac/ilp32 (the xpack default
#     multilib), -Os -flto -DNDEBUG -fno-exceptions -fno-rtti.
#   * The baseline is linked with the SAME toolchain/libc, so its CRT cancels
#     out of the delta — c-riscv (apt toolchain, picolibc) stays comparable:
#     each target's delta is against its own baseline.
#   * The binaries are never executed — this target measures size only.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
EP="${EP:-$ROOT/vendor/EmbeddedProto}"
GEN_SOFAB="$ROOT/languages/cpp-embedded/sofab/gen"
GEN_EP="$ROOT/languages/cpp-embedded/embeddedproto/gen"

# shellcheck source=/dev/null
source "$HERE/toolchain.sh"   # resolves + exports XPACK_GXX / XPACK_GCC
CC="$XPACK_GCC"
CXX="$XPACK_GXX"
ARCH="-march=rv32imac -mabi=ilp32"
CFLAGS="$ARCH -Os -flto -DNDEBUG -ffunction-sections -fdata-sections"
CXXFLAGS="$CFLAGS -fno-exceptions -fno-rtti"
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
    printf 'FOOTPRINT lang=cpp-riscv impl=%s text=%s rodata=%s data=%s bss=%s\n' "$impl" "$t" "$r" "$d" "$b"
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
HARNESS static std::uint8_t buf[512];
HARNESS volatile std::size_t sink;
int main() {
    std::size_t n = msg.encodeTo(buf, sizeof buf);   // heap-free encode path
    dec = Example::decode(buf, n);                   // fixed-capacity members: heap-free
    sink = n;
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
HARNESS static ::EmbeddedProto::WriteBufferFixedSize<512> wbuf;
HARNESS static ::EmbeddedProto::ReadBufferFixedSize<512> rbuf;
HARNESS volatile int sink;
int main() {
    auto e1 = msg.serialize(wbuf);
    auto e2 = msg.deserialize(rbuf);
    sink = static_cast<int>(e1) + static_cast<int>(e2);
    return 0;
}
EOF
$CXX $CXXFLAGS -std=c++17 $LDFLAGS "$TMP/drv_ep.cpp" \
    "$EP/src/Fields.cpp" "$EP/src/MessageInterface.cpp" "$EP/src/ReadBufferSection.cpp" \
    -I"$GEN_EP" -I"$EP/src" -o "$TMP/ep.elf" >/dev/null
emit_delta embeddedproto "$TMP/ep.elf" "$TMP/baseline.elf"
