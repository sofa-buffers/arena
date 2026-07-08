#!/usr/bin/env bash
# cpp-embedded target setup: generate + compile both benches.
#   * sofab         : SofaBuffers C++ wrapper of corelib-c-cpp (generator
#                     --lang cpp, corelib: c-cpp). corelib C sources are compiled
#                     as C and linked into the C++ bench.
#   * embeddedproto : EmbeddedProto (GPLv3, BUILD-TIME ONLY, fetched into
#                     vendor/EmbeddedProto which is gitignored and NEVER committed).
# Idempotent: fetch EmbeddedProto if absent, regenerate, recompile.
# stderr noise OK; exit 0 on success.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
EP="${EP:-$ROOT/vendor/EmbeddedProto}"
COMMON="$ROOT/languages/common"
CXX="${CXX:-g++}"
CC="${CC:-gcc}"
# Embedded C++ flags: no exceptions / RTTI / unwind tables — how EmbeddedProto and
# the corelib C++ wrapper are meant to be built for firmware. Applied only to the
# C++ (bench) compiles, not the C corelib sources. Keep in sync with footprint.sh.
CXXEMB="-fno-exceptions -fno-rtti -fno-unwind-tables -fno-asynchronous-unwind-tables -fno-threadsafe-statics"

# --- SofaBuffers C++ wrapper of corelib-c-cpp ------------------------------
mkdir -p "$HERE/sofab/gen"
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang cpp \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >&2

OBJ="$(mktemp -d)"
trap 'rm -rf "$OBJ"' EXIT
# corelib-c-cpp ships C sources: compile them as C, then link into the C++ bench.
$CC -Os -flto -std=c99 -c \
    "$CORELIB/src/object.c" "$CORELIB/src/ostream.c" "$CORELIB/src/istream.c" \
    -I"$CORELIB/src/include"
$CC -Os -flto -std=c99 -c "$COMMON/sha256.c" -I"$COMMON"
mv ./*.o "$OBJ"/
$CXX -Os -flto $CXXEMB -std=c++20 \
    -I"$HERE/sofab/gen" -I"$CORELIB/src/include" -I"$COMMON" \
    "$HERE/sofab/bench.cpp" "$OBJ"/*.o \
    -o "$HERE/sofab/bench" >&2

# --- EmbeddedProto ---------------------------------------------------------
# 1) fetch (idempotent: skip if already cloned). GPLv3 -> gitignored, never committed.
if [ ! -d "$EP/.git" ]; then
    git clone --depth 1 https://github.com/Embedded-AMS/EmbeddedProto.git "$EP" >&2
fi
# 2) create the generator's self-contained python venv (idempotent). Recreate
#    it when broken, not just missing — an image rebuild that upgrades the base
#    Python leaves the venv present but unable to start its interpreter.
if ! "$EP/venv/bin/python3" -c '' >/dev/null 2>&1; then
    rm -rf "$EP/venv"
    ( cd "$EP" && python3 setup.py --ignore_version_diff >&2 )
fi
# 3) generate C++ from the EmbeddedProto-annotated local proto (custom field
#    options set fixed max sizes; -I ./generator resolves embedded_proto_options.proto).
mkdir -p "$HERE/embeddedproto/gen"
( cd "$EP" && protoc --plugin=protoc-gen-eams="$EP/protoc-gen-eams" \
    -I "$HERE/embeddedproto/proto" -I "$EP/generator" \
    --eams_out="$HERE/embeddedproto/gen" \
    "$HERE/embeddedproto/proto/message.proto" >&2 )
# 4) compile bench + generated header + EmbeddedProto runtime sources + sha256.
$CXX -Os -flto $CXXEMB -std=c++17 \
    -I"$HERE/embeddedproto/gen" -I"$EP/src" -I"$COMMON" \
    "$HERE/embeddedproto/bench.cpp" \
    "$EP/src/Fields.cpp" "$EP/src/MessageInterface.cpp" "$EP/src/ReadBufferSection.cpp" \
    "$COMMON/sha256.c" \
    -o "$HERE/embeddedproto/bench" >&2

echo "cpp-embedded: setup OK" >&2
