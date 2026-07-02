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

# Portable GC tuning for this allocation-heavy, single-threaded microbench
# (applied to BOTH impls so the comparison stays fair). No CPU/ISA pinning.
#   gcServer=0/gcConcurrent=0  Workstation, non-concurrent GC: no background GC
#                              thread; Server GC was measurably slower here.
#   GCgen0size=0x4000000       64 MB gen0 budget -> far fewer gen0 collections
#                              (a bounded, memory-safe analog of Go's GOGC=400).
#   TieredPGO is already the .NET 9 default; set explicitly for clarity.
export DOTNET_gcServer="${DOTNET_gcServer:-0}"
export DOTNET_gcConcurrent="${DOTNET_gcConcurrent:-0}"
export DOTNET_GCgen0size="${DOTNET_GCgen0size:-0x4000000}"
export DOTNET_TieredPGO="${DOTNET_TieredPGO:-1}"

dotnet "$HERE/sofab/bench/bin/Release/net9.0/sofab_bench.dll"
dotnet "$HERE/protobuf/bin/Release/net9.0/protobuf_bench.dll"
