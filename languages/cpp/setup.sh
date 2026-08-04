#!/usr/bin/env bash
# C++ target setup: generate sofab + protobuf C++ code and compile both bench
# executables. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
COMMON="$ROOT/languages/common"
CXX="${CXX:-g++}"
CXXFLAGS="-O3 -march=native -flto -std=c++20"

# Buffer the streaming impls render through, deliberately far below the ~434/494 B
# message so the drain path is actually exercised. ONE value for both sides of the
# row: the streaming rows compare codecs, not harness granularity (#108).
STREAM_BUF_BYTES="${STREAM_BUF_BYTES:-64}"

# --- sofab: generate the typed C++ header against corelib-cpp ---------------
# Two storage profiles, one corelib and one driver (#107): sofab/cfg.yaml keeps
# allow_dynamic on (std::string/std::vector), sofab-heapfree/cfg.yaml turns it
# off (sofab::FixedString/FixedBytes/InlineVector — nothing on the heap). Both
# compile the SAME sofab/bench.cpp with the SAME $CXXFLAGS; only the generated
# header on the include path and -DBENCH_IMPL differ, so the pair isolates the
# storage axis and nothing else.
for variant in sofab sofab-heapfree; do
    mkdir -p "$HERE/$variant/gen"
    "$SOFABGEN" --config "$HERE/$variant/cfg.yaml" --lang cpp \
        --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/$variant/gen" >/dev/null

    $CXX $CXXFLAGS \
        -DBENCH_IMPL="\"$variant\"" \
        -I "$HERE/$variant/gen" \
        -I "$ROOT/vendor/corelib-cpp/include" \
        -I "$COMMON" \
        "$HERE/sofab/bench.cpp" "$COMMON/sha256.c" \
        -o "$HERE/$variant/bench"
done

# sofab-stream (#108): the growable codegen again — this variant changes the
# ENCODE PATH, not the storage — driven through a bounded buffer + flush sink.
$CXX $CXXFLAGS \
    -DBENCH_IMPL='"sofab-stream"' -DBENCH_STREAM -DSTREAM_BUF_BYTES="$STREAM_BUF_BYTES" \
    -I "$HERE/sofab/gen" \
    -I "$ROOT/vendor/corelib-cpp/include" \
    -I "$COMMON" \
    "$HERE/sofab/bench.cpp" "$COMMON/sha256.c" \
    -o "$HERE/sofab/bench-stream"

# --- protobuf: generate message.pb.{h,cc} and compile -----------------------
mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" --cpp_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"

PROTO_LIBS="$(pkg-config --cflags --libs protobuf 2>/dev/null || echo "-lprotobuf")"

$CXX $CXXFLAGS \
    -DBENCH_IMPL='"protobuf"' \
    -I "$HERE/protobuf/gen" \
    -I "$COMMON" \
    "$HERE/protobuf/bench.cpp" "$HERE/protobuf/gen/message.pb.cc" "$COMMON/sha256.c" \
    -o "$HERE/protobuf/bench" \
    $PROTO_LIBS

# protobuf-stream: the opponent of sofab-stream. Same flags, same driver source,
# same STREAM_BUF_BYTES — only SerializeToZeroCopyStream instead of
# SerializeToString.
$CXX $CXXFLAGS \
    -DBENCH_IMPL='"protobuf-stream"' -DBENCH_STREAM -DSTREAM_BUF_BYTES="$STREAM_BUF_BYTES" \
    -I "$HERE/protobuf/gen" \
    -I "$COMMON" \
    "$HERE/protobuf/bench.cpp" "$HERE/protobuf/gen/message.pb.cc" "$COMMON/sha256.c" \
    -o "$HERE/protobuf/bench-stream" \
    $PROTO_LIBS

echo "cpp: setup OK" >&2
