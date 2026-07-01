#!/usr/bin/env bash
# TypeScript target: run both impls with node (via tsx), print BENCH lines.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export PROTO_PATH="${PROTO_PATH:-$ROOT/schema/message.proto}"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

( cd "$HERE/sofab/gen" && npx --no-install tsx bench.ts )
( cd "$HERE/protobuf" && npx --no-install tsx bench.ts )
