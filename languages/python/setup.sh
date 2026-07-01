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

# sofab: build corelib-py's optional native (Cython) accelerator in-place so the
# bench imports the compiled `sofab._speedups` (IMPL=native) rather than the
# pure-Python fallback. Tolerant: if the compile fails the bench still runs pure.
"$PY" -m pip install -q --disable-pip-version-check "Cython>=3.0" setuptools wheel >/dev/null 2>&1 || true
if ( cd "$ROOT/vendor/corelib-py" && "$PY" setup.py build_ext --inplace >/dev/null 2>&1 ); then
    echo "python: native accelerator built" >&2
else
    echo "python: native build unavailable — pure-Python fallback" >&2
fi

# protobuf: generate message_pb2.py
mkdir -p "$HERE/protobuf/gen"
"$PY" -m grpc_tools.protoc -I "$ROOT/schema" \
    --python_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"

echo "python: setup OK" >&2
