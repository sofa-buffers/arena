#!/usr/bin/env bash
# TypeScript target: run both impls with node (via tsx), print BENCH lines.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export PROTO_PATH="${PROTO_PATH:-$ROOT/schema/message.proto}"
export BENCH_ITERS="${BENCH_ITERS:-500000}"

# Runtime tuning note: the timed region is a warmed, TurboFan-JITed loop that
# pools a single OStream (reset() per iter), so it is GC-light. V8 heap flags
# via NODE_OPTIONS (--max-semi-space-size=64/128/256) were benchmarked and made
# no measurable difference for either impl, so none is applied (defaults keep it
# portable). NODE_OPTIONS is honoured here if a caller wants to override.
[ -n "${NODE_OPTIONS:-}" ] && export NODE_OPTIONS

( cd "$HERE/sofab/gen" && npx --no-install tsx bench.ts )
( cd "$HERE/protobuf" && npx --no-install tsx bench.ts )
