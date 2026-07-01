#!/usr/bin/env bash
# C target setup: generate sofab (--lang c) + protobuf-c bindings and compile
# both bench executables. Idempotent. stderr noise OK; exit 0 on success.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
COMMON="$ROOT/languages/common"
BENCHINC="$ROOT/old-repo/src/common"   # bench.h timing harness

# --- SofaBuffers C ---------------------------------------------------------
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang c \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >&2

gcc -O2 -std=c99 \
    "$HERE/sofab/bench.c" \
    "$HERE"/sofab/gen/*.c \
    "$CORELIB/src/object.c" "$CORELIB/src/ostream.c" "$CORELIB/src/istream.c" \
    "$COMMON/sha256.c" \
    -I"$CORELIB/src/include" -I"$HERE/sofab/gen" -I"$COMMON" -I"$BENCHINC" \
    -o "$HERE/sofab/bench" >&2

# --- protobuf-c ------------------------------------------------------------
mkdir -p "$HERE/protobuf/gen"
protoc-c --c_out="$HERE/protobuf/gen" -I "$ROOT/schema" "$ROOT/schema/message.proto" >&2

gcc -O2 -std=c99 \
    "$HERE/protobuf/bench.c" \
    "$HERE"/protobuf/gen/*.c \
    "$COMMON/sha256.c" \
    -I"$HERE/protobuf/gen" -I"$COMMON" -I"$BENCHINC" \
    -lprotobuf-c \
    -o "$HERE/protobuf/bench" >&2

echo "c: setup OK" >&2
