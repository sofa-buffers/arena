#!/usr/bin/env bash
# C# target setup: generate + build sofab and protobuf bindings. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"

export PATH="/usr/local/dotnet:$PATH"
export DOTNET_ROOT="/usr/local/dotnet"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export SOFAB_CS_CORELIB="${SOFAB_CS_CORELIB:-$ROOT/vendor/corelib-cs}"

# sofab: generate the typed C# message library (namespace Sofabuffers) against corelib-cs.
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang csharp \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >/dev/null

( cd "$HERE/sofab/bench" && dotnet build -c Release -v q >/dev/null )

# protobuf: generate C# bindings from message.proto into a Google.Protobuf project.
mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" --csharp_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"
( cd "$HERE/protobuf" && dotnet build -c Release -v q >/dev/null )

echo "csharp: setup OK" >&2
