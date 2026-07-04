#!/usr/bin/env bash
#
# bootstrap.sh — one-time project setup, independent of any language target.
#
#   1. downloads the prebuilt `sofabgen` (the SofaBuffers code generator) for the
#      host platform into tools/  (the SofaBuffers analogue of protoc)
#   2. creates tools/venv with the Python protobuf compiler + runtime, used by
#      the protobuf targets that generate via grpcio-tools (Python) and by the
#      Python benchmark itself
#
# The protobuf per-language runtimes are fetched by each languages/<lang>/setup.sh
# at build time (cargo/npm/go/maven/nuget/pip). The SofaBuffers corelibs are
# cloned here into vendor/ (one per language) so every setup.sh finds them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p tools vendor

# --- SofaBuffers corelibs (one per language backend) --------------------------
CORELIBS="corelib-py corelib-c-cpp corelib-cpp corelib-go corelib-rs corelib-rs-no-std corelib-java corelib-cs corelib-ts"

# v0.6.0 folded the Rust/Java/C#/Go decode perf patches into codegen; v0.7.0
# added the cpp fixed-capacity (FixedString) profile; v0.8.0 moved
# FixedBytes/InlineVector into corelib-c-cpp (needs a fresh corelib clone);
# v0.9.0 makes `corelib: rs-no-std` emit genuinely no_std, heap-free Rust
# (enables the rust bare-metal footprint targets); v0.10.0 emits schema
# defaults as a const image on the C path (non-zero defaults honored); v0.11.0
# sparsely omits default string/blob wrapper-array elements across all backends
# (needs fresh corelibs whose decoders place elements by id, not arrival order),
# so every sofab wire converges on one length. Bump together with whatever
# generated-code contract the targets rely on.
SOFABGEN_VERSION="${SOFABGEN_VERSION:-v0.11.0}"

# A version bump must invalidate BOTH the prebuilt sofabgen binary and the
# corelib clones — v0.11.0's decoders place wrapper-array elements by id, so a
# stale corelib silently produces the wrong wire. The clone/download guards
# below are purely presence-based, so without this stamp a checkout that already
# ran an older bootstrap would keep serving the old toolchain. Re-run bootstrap
# after bumping SOFABGEN_VERSION and the stamp mismatch forces a clean refresh.
STAMP="tools/.sofabgen-version"
if [ "$(cat "$STAMP" 2>/dev/null || true)" != "$SOFABGEN_VERSION" ]; then
    [ -x tools/sofabgen ] && echo "==> sofabgen version -> $SOFABGEN_VERSION; refreshing binary + corelibs"
    rm -f tools/sofabgen
    for r in $CORELIBS; do rm -rf "vendor/$r"; done
fi

for r in $CORELIBS; do
    if [ ! -d "vendor/$r" ]; then
        echo "==> cloning $r"
        git clone --depth 1 "https://github.com/sofa-buffers/$r.git" "vendor/$r" >/dev/null 2>&1 \
            || { echo "!! failed to clone $r"; exit 1; }
    fi
done

# --- host os/arch -> release asset name (mirrors the old CMake logic) ---------
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in linux) OS=linux;; darwin) OS=darwin;; *) OS=linux;; esac
arch="$(uname -m)"
case "$arch" in
    x86_64|amd64)  A=amd64;;
    aarch64|arm64) A=arm64;;
    i386|i686)     A=386;;
    arm*)          A=arm;;
    *)             A=amd64;;
esac
ASSET="sofabgen-${OS}-${A}"

if [ ! -x tools/sofabgen ]; then
    URL="https://github.com/sofa-buffers/generator/releases/download/${SOFABGEN_VERSION}/${ASSET}"
    echo "==> downloading sofabgen ${SOFABGEN_VERSION} ($ASSET)"
    # Public release; if a token is present (e.g. private mirror) use it.
    AUTH=()
    if [ -f "$ROOT/.devcontainer/.env" ]; then
        TOK="$(sed -n 's/^GITHUB_TOKEN=//p' "$ROOT/.devcontainer/.env" | head -1)"
        [ -n "${TOK:-}" ] && AUTH=(-H "Authorization: Bearer $TOK")
    fi
    curl -fsSL "${AUTH[@]}" "$URL" -o tools/sofabgen
    chmod +x tools/sofabgen
fi
# Stamp the resolved version so a future bump (and only a bump) forces a refresh.
echo "$SOFABGEN_VERSION" > "$STAMP"
echo "==> sofabgen: $(tools/sofabgen -version 2>/dev/null || echo present)"

# --- python venv for the protobuf compiler + runtime --------------------------
if [ ! -x tools/venv/bin/python ]; then
    echo "==> creating tools/venv (protobuf + grpcio-tools)"
    python3 -m venv tools/venv
    tools/venv/bin/python -m pip install --upgrade pip >/dev/null
    tools/venv/bin/python -m pip install "protobuf==4.25.3" grpcio-tools >/dev/null
fi
echo "==> python protobuf: $(tools/venv/bin/python -c 'import google.protobuf as p; print(p.__version__)')"

echo "bootstrap OK"
