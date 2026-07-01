#!/usr/bin/env bash
# Python target setup: generate sofab + protobuf bindings. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
PY="${PYBIN:-$ROOT/tools/venv/bin/python}"

# sofab: generate the typed message library against corelib-py
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang python \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >/dev/null

# protobuf: generate message_pb2.py
mkdir -p "$HERE/protobuf/gen"
"$PY" -m grpc_tools.protoc -I "$ROOT/schema" \
    --python_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"

echo "python: setup OK" >&2
