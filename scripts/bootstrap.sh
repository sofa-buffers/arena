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
# The corelibs and the sofabgen generator move in lockstep, and this arena
# intentionally follows the NEWEST of both: every bootstrap run pulls each corelib
# to its remote default-branch (main) HEAD and downloads the sofabgen binary from
# the generator's most recent SUCCESSFUL CI build on main — its per-commit build
# artifact, NOT a tagged release, so the arena tracks the true generator tip
# rather than lagging behind the release cadence. Nothing is pinned here — the
# cross-language wire gate in run_benchmark.sh (sofab 434 B / proto 494 B) is what
# catches a generator/corelib change that moves the wire.
#
# For a reproducible run, pin a specific CI build with SOFABGEN_RUN_ID=<run-id>
# (the corelibs still follow main HEAD — check out a matching corelib commit by
# hand if a fully frozen toolchain is needed).
#
# NOTE: fetching a CI artifact (unlike the old release asset) REQUIRES a GitHub
# token — the Actions artifacts API is auth-only even for public repos. It is
# read from GITHUB_TOKEN in .devcontainer/.env just below.
CORELIBS="corelib-py corelib-c-cpp corelib-cpp corelib-go corelib-rs corelib-rs-no-std corelib-java corelib-cs corelib-ts corelib-zig corelib-dart"

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

# --- host os/arch -> CI artifact name (mirrors the old release-asset naming) ---
# The generator's CI uploads one binary per platform as a workflow artifact named
# exactly like the old release asset (sofabgen-<os>-<arch>); pick ours.
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

# --- resolve the sofabgen CI build to fetch -----------------------------------
# Default: the newest SUCCESSFUL run of the generator's CI workflow on main. Pin
# a specific build with SOFABGEN_RUN_ID=<id>. The workflow run id is stable per
# build and is what gets stamped, so an unchanged tip doesn't re-download.
GEN_API="https://api.github.com/repos/sofa-buffers/generator"
STAMP="tools/.sofabgen-version"   # now holds the resolved workflow run id

RUN_ID="${SOFABGEN_RUN_ID:-}"
if [ -z "$RUN_ID" ]; then
    RUN_ID="$(curl -fsSL "${AUTH[@]}" \
        "$GEN_API/actions/workflows/ci.yml/runs?branch=main&status=success&per_page=1" 2>/dev/null \
        | jq -r '.workflow_runs[0].id // empty' 2>/dev/null || true)"
fi
if [ -z "$RUN_ID" ]; then
    # No network / API failed / no token: fall back to whatever binary is already
    # present so an offline re-run still works; only hard-fail with nothing to reuse.
    RUN_ID="$(cat "$STAMP" 2>/dev/null || true)"
    if [ -x tools/sofabgen ] && [ -n "$RUN_ID" ]; then
        echo "!! could not resolve latest sofabgen CI run; keeping present (run $RUN_ID)"
    else
        echo "!! could not resolve latest sofabgen CI run and no binary is present" >&2
        echo "!! (a GITHUB_TOKEN in .devcontainer/.env is required to fetch the artifact)" >&2
        exit 1
    fi
fi

# Force a re-download when the resolved run differs from the stamped one: the
# download guard below is presence-based, so without this a checkout that already
# has an older binary would keep serving it even though a newer build now exists.
if [ "$(cat "$STAMP" 2>/dev/null || true)" != "$RUN_ID" ]; then
    [ -x tools/sofabgen ] && echo "==> sofabgen -> CI run $RUN_ID; refreshing binary"
    rm -f tools/sofabgen
fi

if [ ! -x tools/sofabgen ]; then
    if [ "${#AUTH[@]}" -eq 0 ]; then
        echo "!! fetching the sofabgen CI artifact needs a token; set GITHUB_TOKEN in .devcontainer/.env" >&2
        exit 1
    fi
    # Find our platform's artifact in that run, then download its zip (the Actions
    # artifacts API always hands back a zip wrapping the binary + its .sha256).
    ART_ID="$(curl -fsSL "${AUTH[@]}" \
        "$GEN_API/actions/runs/$RUN_ID/artifacts?per_page=100" 2>/dev/null \
        | jq -r --arg n "$ASSET" 'first(.artifacts[] | select(.name==$n and .expired==false) | .id) // empty' 2>/dev/null || true)"
    if [ -z "$ART_ID" ]; then
        echo "!! CI run $RUN_ID has no (unexpired) artifact named $ASSET" >&2; exit 1
    fi
    echo "==> downloading sofabgen artifact $ASSET (CI run $RUN_ID)"
    TMP="$(mktemp -d)"
    curl -fsSL "${AUTH[@]}" "$GEN_API/actions/artifacts/$ART_ID/zip" -o "$TMP/art.zip"
    unzip -q -o "$TMP/art.zip" -d "$TMP"
    # Verify the bundled checksum before trusting the binary (the artifact ships a
    # standard sha256sum line: "<hash>  <name>").
    ( cd "$TMP" && sha256sum -c "${ASSET}.sha256" >/dev/null ) \
        || { echo "!! sofabgen artifact checksum mismatch"; rm -rf "$TMP"; exit 1; }
    install -m 0755 "$TMP/$ASSET" tools/sofabgen
    rm -rf "$TMP"
fi
# Stamp the resolved run id so an unchanged tip doesn't re-download next run.
echo "$RUN_ID" > "$STAMP"
echo "==> sofabgen: $(tools/sofabgen -version 2>/dev/null || echo present) (CI run $RUN_ID)"

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
