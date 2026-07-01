#!/usr/bin/env bash
# C++ target setup: generate sofab + protobuf C++ code and compile both bench
# executables. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
COMMON="$ROOT/languages/common"
CXX="${CXX:-g++}"
CXXFLAGS="-O2 -std=c++20"

# --- sofab: generate the typed C++ header against corelib-cpp ---------------
mkdir -p "$HERE/sofab/gen"
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang cpp \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >/dev/null

$CXX $CXXFLAGS \
    -I "$HERE/sofab/gen" \
    -I "$ROOT/vendor/corelib-cpp/include" \
    -I "$COMMON" \
    "$HERE/sofab/bench.cpp" "$COMMON/sha256.c" \
    -o "$HERE/sofab/bench"

# --- protobuf: generate message.pb.{h,cc} and compile -----------------------
mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" --cpp_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"

$CXX $CXXFLAGS \
    -I "$HERE/protobuf/gen" \
    -I "$COMMON" \
    "$HERE/protobuf/bench.cpp" "$HERE/protobuf/gen/message.pb.cc" "$COMMON/sha256.c" \
    -o "$HERE/protobuf/bench" \
    $(pkg-config --cflags --libs protobuf 2>/dev/null || echo "-lprotobuf")

echo "cpp: setup OK" >&2
