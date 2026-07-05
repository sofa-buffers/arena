#!/usr/bin/env bash
# typescript-bun bench: run the TypeScript target's sofab + protobufjs benches
# under Bun (JavaScriptCore) instead of Node/tsx (V8). Reuses the same generated
# code and node_modules; only the runtime differs. Emits BENCH lines retagged
# lang=typescript-bun so the runner tables it as its own runtime row.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TS="$ROOT/languages/typescript"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export PROTO_PATH="${PROTO_PATH:-$ROOT/schema/message.proto}"
export BENCH_ITERS="${BENCH_ITERS:-500000}"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"
command -v bun >/dev/null || { echo "FAIL: bun not on PATH" >&2; exit 1; }

retag() { sed -E 's/lang=typescript /lang=typescript-bun /'; }

( cd "$TS/sofab/gen" && bun run bench.ts | retag )
( cd "$TS/protobuf" && bun run bench.ts | retag )
