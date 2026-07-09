#!/usr/bin/env bash
# TypeScript target setup: build corelib-ts, generate sofab bindings, wire the
# corelib dependency, and set up the protobufjs side. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="${SOFAB_TS_CORELIB:-$ROOT/vendor/corelib-ts}"
# Central pins for the generated package.json (see versions.sh header);
# renovate.json ignores sofab/gen so Renovate never fights these.
. "$ROOT/languages/versions.sh"

# (1) Build corelib-ts if its dist/ is missing.
if [ ! -f "$CORELIB/dist/index.js" ]; then
    echo "typescript: building corelib-ts" >&2
    ( cd "$CORELIB" && npm install --no-audit --no-fund --silent && npm run build >/dev/null )
fi
[ -f "$CORELIB/dist/index.js" ] || { echo "FAIL: corelib-ts not built (no dist/)" >&2; exit 1; }

# (2) Generate the sofab TypeScript project, wire the corelib dependency, install.
GEN="$HERE/sofab/gen"
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang typescript \
    --in "$ROOT/schema/message.sofab.yaml" --out "$GEN" >/dev/null

# Wire the corelib link and force the arena-pinned devDeps: sofabgen's template
# ships older ranges than the arena tracks, and this file is Renovate-ignored
# (renovate.json), so setup.sh is the source of truth. Keep @types/node /
# typescript / tsx in lockstep with the hand-written protobuf/package.json.
node -e "const p=require('$GEN/package.json');p.dependencies['@sofa-buffers/corelib']='file:$CORELIB';p.devDependencies={...p.devDependencies,'@types/node':'$TS_TYPES_NODE','typescript':'$TS_TYPESCRIPT','tsx':'$TS_TSX'};require('fs').writeFileSync('$GEN/package.json',JSON.stringify(p,null,2))"
# Drop any stale lockfile/tree: it pins the checkout-specific vendor/corelib-ts
# path via a `file:` link, so a re-cloned (or moved) vendor leaves the lock's
# link target dangling and npm aborts with EMISSINGTARGET. sofabgen regenerates
# package.json but never the lock, so clear it here and let npm resolve fresh.
rm -rf "$GEN/package-lock.json" "$GEN/node_modules/@sofa-buffers"
( cd "$GEN" && npm install --no-audit --no-fund --silent ) \
    || ( cd "$GEN" && npm install --no-audit --no-fund )

# The bench program lives beside the generated message.ts so that both
# `@sofa-buffers/corelib` and `./message.js` resolve from the generated project.
cp "$HERE/sofab/bench.ts" "$GEN/bench.ts"

# (3) Protobuf side: protobufjs (+ long for exact 64-bit) and a tsx runner.
PB="$HERE/protobuf"
if [ ! -f "$PB/package.json" ]; then
    cat > "$PB/package.json" <<'JSON'
{
  "name": "typescript-protobuf-bench",
  "private": true,
  "type": "module"
}
JSON
fi
( cd "$PB" && npm install --no-audit --no-fund --silent protobufjs long tsx typescript @types/node ) \
    || ( cd "$PB" && npm install --no-audit --no-fund protobufjs long tsx typescript @types/node )

echo "typescript: setup OK" >&2
