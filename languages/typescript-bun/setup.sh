#!/usr/bin/env bash
# typescript-bun setup: the Bun (JavaScriptCore) runtime for the TypeScript
# target. It reuses the *identical* generated sofab code + protobufjs baseline as
# the `typescript` (Node/V8) target — only the runtime differs — so there is no
# separate codegen here. Bun is normally provided by the devcontainer image; this
# also installs it on demand so a bare host still works. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/languages/versions.sh"   # BUN_VERSION

export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"
if ! command -v bun >/dev/null 2>&1; then
    echo "typescript-bun: bun not found, installing bun $BUN_VERSION" >&2
    curl -fsSL https://bun.sh/install | bash -s "bun-v$BUN_VERSION" >&2
fi
command -v bun >/dev/null || { echo "FAIL: bun unavailable" >&2; exit 1; }

# Reuse the Node target's generated project (sofab/gen + protobuf). Always run
# its (idempotent) setup so a stale corelib build or generated code is refreshed
# here too, not only when the typescript target ran first.
"$ROOT/languages/typescript/setup.sh" >&2

echo "typescript-bun: setup OK (bun $(bun --version))" >&2
