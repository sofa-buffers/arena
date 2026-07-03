#!/usr/bin/env bash
# TypeScript target setup: build corelib-ts, generate sofab bindings, wire the
# corelib dependency, and set up the protobufjs side. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="${SOFAB_TS_CORELIB:-$ROOT/vendor/corelib-ts}"

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

# Perf: re-apply the monomorphic pull-decode optimization. sofabgen emits a
# push/visitor decoder (`decode(bytes, this._visitor())`) whose per-field call
# sites go megamorphic once one decode routes through several visitor shapes, so
# V8 cannot inline them; it also allocates ~5 visitor objects + ChunkAccs per
# decode (two of them dead). This patch emits a monomorphic `decodeFrom(Cursor)`
# per type — one `switch(id)` reading straight into fields off the corelib's
# pull-style Cursor (see docs/perf-patches/typescript-monomorphic-decode.md).
# Generator-spec patch — fold into codegen upstream. Idempotent (marker-guarded).
if ! grep -q "decodeFrom" "$GEN/message.ts"; then
    patch -p1 -d "$GEN" < "$HERE/sofab/monomorphic-decode.patch" >&2
fi

node -e "const p=require('$GEN/package.json');p.dependencies['@sofa-buffers/corelib']='file:$CORELIB';require('fs').writeFileSync('$GEN/package.json',JSON.stringify(p,null,2))"
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
