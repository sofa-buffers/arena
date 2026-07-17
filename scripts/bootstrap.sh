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

# --- SofaBuffers corelibs + generator: track the bleeding edge -----------------
# The corelibs and the sofabgen generator release in lockstep, and this arena
# intentionally follows the NEWEST of both: every bootstrap run pulls each corelib
# to its remote default-branch (main) HEAD and downloads the latest sofabgen
# release. Nothing is pinned here — the cross-language wire gate in
# run_benchmark.sh (sofab 434 B / proto 494 B) is what catches a generator/corelib
# change that moves the wire, and the per-release history lives on the generator
# repo's Releases page rather than in this file.
#
# For a reproducible run, pin the generator with SOFABGEN_VERSION=vX.Y.Z (the
# corelibs still follow main HEAD — check out a matching corelib tag by hand if a
# fully frozen toolchain is needed).
CORELIBS="corelib-py corelib-c-cpp corelib-cpp corelib-go corelib-rs corelib-rs-no-std corelib-java corelib-cs corelib-ts corelib-zig"

# A token lifts the GitHub API rate limit and reaches a private mirror if one is
# configured; reused for both the release lookup and the binary download.
AUTH=()
if [ -f "$ROOT/.devcontainer/.env" ]; then
    TOK="$(sed -n 's/^GITHUB_TOKEN=//p' "$ROOT/.devcontainer/.env" | head -1)"
    [ -n "${TOK:-}" ] && AUTH=(-H "Authorization: Bearer $TOK")
fi

# Always update each corelib to its remote default branch (main, else master) HEAD.
# Shallow fetch + hard reset pins the clone to exactly the upstream tip with no
# local divergence, so a moved branch can never leave a stale wire behind.
for r in $CORELIBS; do
    dir="vendor/$r"
    if [ ! -d "$dir/.git" ]; then
        rm -rf "$dir"
        echo "==> cloning $r"
        git clone --depth 1 "https://github.com/sofa-buffers/$r.git" "$dir" >/dev/null 2>&1 \
            || { echo "!! failed to clone $r"; exit 1; }
    fi
    if   git -C "$dir" fetch --depth 1 --quiet origin main   2>/dev/null; then :
    elif git -C "$dir" fetch --depth 1 --quiet origin master 2>/dev/null; then :
    else echo "!! failed to fetch $r from origin"; exit 1; fi
    git -C "$dir" reset --hard --quiet FETCH_HEAD
    echo "==> $r @ $(git -C "$dir" rev-parse --short HEAD)"
done

# --- resolve the sofabgen release to fetch ------------------------------------
# Default: the LATEST published release, resolved from the GitHub API. Pin with
# SOFABGEN_VERSION=vX.Y.Z to fetch a specific release instead.
SOFABGEN_VERSION="${SOFABGEN_VERSION:-latest}"
STAMP="tools/.sofabgen-version"
if [ "$SOFABGEN_VERSION" = latest ]; then
    RESOLVED="$(curl -fsSL "${AUTH[@]}" \
        "https://api.github.com/repos/sofa-buffers/generator/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [ -z "$RESOLVED" ]; then
        # No network / API failed: fall back to whatever is already present so an
        # offline re-run still works, and only hard-fail if there is nothing to
        # fall back to.
        RESOLVED="$(cat "$STAMP" 2>/dev/null || true)"
        if [ -x tools/sofabgen ] && [ -n "$RESOLVED" ]; then
            echo "!! could not resolve latest sofabgen release; keeping present ($RESOLVED)"
        else
            echo "!! could not resolve latest sofabgen release and no binary is present" >&2; exit 1
        fi
    fi
else
    RESOLVED="$SOFABGEN_VERSION"
fi

# Force a re-download when the resolved release differs from the stamped one: the
# download guard below is presence-based, so without this a checkout that already
# has an older binary would keep serving it even though a newer release now exists.
if [ "$(cat "$STAMP" 2>/dev/null || true)" != "$RESOLVED" ]; then
    [ -x tools/sofabgen ] && echo "==> sofabgen -> $RESOLVED; refreshing binary"
    rm -f tools/sofabgen
fi

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
    URL="https://github.com/sofa-buffers/generator/releases/download/${RESOLVED}/${ASSET}"
    echo "==> downloading sofabgen ${RESOLVED} ($ASSET)"
    curl -fsSL "${AUTH[@]}" "$URL" -o tools/sofabgen
    chmod +x tools/sofabgen
fi
# Stamp the resolved version so an unchanged latest doesn't re-download next run.
echo "$RESOLVED" > "$STAMP"
echo "==> sofabgen: $(tools/sofabgen -version 2>/dev/null || echo present)"

# --- python venv for the protobuf compiler + runtime + Cython -----------------
# Recreate the venv when it's missing OR broken: an image rebuild that upgrades
# the base Python leaves the venv present but unusable, which a bare [ -x ]
# check doesn't catch. protobuf 4.x has no grpcio-tools build for Python 3.14+.
# Cython lives here too (the venv is isolated from the system cython3), so the
# python target's native accelerator builds without a bench-time pip install;
# the guard imports it as well so an older venv is rebuilt to pick it up.
if ! tools/venv/bin/python -c 'import grpc_tools.protoc, Cython' >/dev/null 2>&1; then
    echo "==> creating tools/venv (protobuf + grpcio-tools + Cython)"
    rm -rf tools/venv
    python3 -m venv tools/venv
    tools/venv/bin/python -m pip install --upgrade pip >/dev/null
    tools/venv/bin/python -m pip install "protobuf==7.35.1" "grpcio-tools==1.82.1" "Cython>=3.0" setuptools wheel >/dev/null
fi
echo "==> python protobuf: $(tools/venv/bin/python -c 'import google.protobuf as p; print(p.__version__)')"

echo "bootstrap OK"
