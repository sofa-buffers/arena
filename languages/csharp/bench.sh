#!/usr/bin/env bash
# C# target: run both impls, print EXACTLY two BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

export PATH="/usr/local/dotnet:$PATH"
export DOTNET_ROOT="/usr/local/dotnet"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

dotnet "$HERE/sofab/bench/bin/Release/net9.0/sofab_bench.dll"
dotnet "$HERE/protobuf/bin/Release/net9.0/protobuf_bench.dll"
