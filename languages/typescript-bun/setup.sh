#!/usr/bin/env bash
# typescript-bun setup: the Bun (JavaScriptCore) runtime for the TypeScript
# target. It reuses the *identical* generated sofab code + protobufjs baseline as
# the `typescript` (Node/V8) target — only the runtime differs — so there is no
# separate codegen here. Bun is normally provided by the devcontainer image; this
# also installs it on demand so a bare host still works. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"
if ! command -v bun >/dev/null 2>&1; then
    echo "typescript-bun: bun not found, installing" >&2
    curl -fsSL https://bun.sh/install | bash >&2
fi
command -v bun >/dev/null || { echo "FAIL: bun unavailable" >&2; exit 1; }

# Reuse the Node target's generated project (sofab/gen + protobuf). LANGS runs
# `typescript` before `typescript-bun`, so this is already set up; generate it
# here too if this target is run in isolation.
if [ ! -f "$ROOT/languages/typescript/sofab/gen/bench.ts" ]; then
    echo "typescript-bun: generating the typescript target first" >&2
    "$ROOT/languages/typescript/setup.sh" >&2
fi

echo "typescript-bun: setup OK (bun $(bun --version))" >&2
