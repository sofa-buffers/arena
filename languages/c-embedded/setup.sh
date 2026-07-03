#!/usr/bin/env bash
# C target setup: generate sofab (--lang c) + protobuf-c bindings and compile
# both bench executables. Idempotent. stderr noise OK; exit 0 on success.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="${CORELIB:-$ROOT/vendor/corelib-c-cpp}"
NANOPB="${NANOPB:-$ROOT/vendor/nanopb}"
COMMON="$ROOT/languages/common"
BENCHINC="$HERE"   # bench.h timing harness (lives with this target)

# --- SofaBuffers C ---------------------------------------------------------
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang c \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >&2

gcc -Os -flto -std=c99 \
    "$HERE/sofab/bench.c" \
    "$HERE"/sofab/gen/*.c \
    "$CORELIB/src/object.c" "$CORELIB/src/ostream.c" "$CORELIB/src/istream.c" \
    "$COMMON/sha256.c" \
    -I"$CORELIB/src/include" -I"$HERE/sofab/gen" -I"$COMMON" -I"$BENCHINC" \
    -o "$HERE/sofab/bench" >&2

# --- protobuf-c ------------------------------------------------------------
mkdir -p "$HERE/protobuf/gen"
protoc-c --c_out="$HERE/protobuf/gen" -I "$ROOT/schema" "$ROOT/schema/message.proto" >&2

gcc -Os -flto -std=c99 \
    "$HERE/protobuf/bench.c" \
    "$HERE"/protobuf/gen/*.c \
    "$COMMON/sha256.c" \
    -I"$HERE/protobuf/gen" -I"$COMMON" -I"$BENCHINC" \
    -lprotobuf-c \
    -o "$HERE/protobuf/bench" >&2

# --- nanopb ----------------------------------------------------------------
# 1) fetch nanopb (idempotent: skip if already cloned)
if [ ! -d "$NANOPB/.git" ]; then
    git clone --depth 1 --branch 0.4.9.1 https://github.com/nanopb/nanopb.git "$NANOPB" >&2 \
        || git clone --depth 1 https://github.com/nanopb/nanopb.git "$NANOPB" >&2
fi

# 2) the nanopb generator needs the python 'protobuf' package; install if absent
if ! python3 -c "import google.protobuf" >/dev/null 2>&1; then
    pip3 install --break-system-packages protobuf >&2 \
        || pip3 install protobuf >&2 || true
fi

# 3) generate message.pb.h / message.pb.c into gen/
mkdir -p "$HERE/nanopb/gen"
python3 "$NANOPB/generator/nanopb_generator.py" \
    -I "$ROOT/schema" -D "$HERE/nanopb/gen" \
    -f "$HERE/nanopb/message.options" \
    "$ROOT/schema/message.proto" >&2

# 4) compile bench + generated code + nanopb runtime + sha256
gcc -Os -flto -std=c99 \
    "$HERE/nanopb/bench.c" \
    "$HERE/nanopb/gen/message.pb.c" \
    "$NANOPB/pb_encode.c" "$NANOPB/pb_decode.c" "$NANOPB/pb_common.c" \
    "$COMMON/sha256.c" \
    -I"$NANOPB" -I"$HERE/nanopb/gen" -I"$COMMON" -I"$BENCHINC" \
    -o "$HERE/nanopb/bench" >&2

echo "c: setup OK" >&2
