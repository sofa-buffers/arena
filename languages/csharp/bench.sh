#!/usr/bin/env bash
# C# target: run both impls, print EXACTLY two BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)

export PATH="/usr/local/dotnet:$PATH"
export DOTNET_ROOT="/usr/local/dotnet"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

# Same runtime settings for both impls; otherwise .NET defaults (workstation
# GC). Non-concurrent GC keeps collections off a background thread -> less jitter.
export DOTNET_gcConcurrent="${DOTNET_gcConcurrent:-0}"

dotnet "$HERE/sofab/bench/bin/Release/net9.0/sofab_bench.dll"
cooldown_between_impls
dotnet "$HERE/protobuf/bin/Release/net9.0/protobuf_bench.dll"
