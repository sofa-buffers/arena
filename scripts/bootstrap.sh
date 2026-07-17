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
CORELIBS="corelib-py corelib-c-cpp corelib-cpp corelib-go corelib-rs corelib-rs-no-std corelib-java corelib-cs corelib-ts corelib-zig"

# v0.6.0 folded the Rust/Java/C#/Go decode perf patches into codegen; v0.7.0
# added the cpp fixed-capacity (FixedString) profile; v0.8.0 moved
# FixedBytes/InlineVector into corelib-c-cpp (needs a fresh corelib clone);
# v0.9.0 makes `corelib: rs-no-std` emit genuinely no_std, heap-free Rust
# (enables the rust bare-metal footprint targets); v0.10.0 emits schema
# defaults as a const image on the C path (non-zero defaults honored); v0.11.0
# sparsely omits default string/blob wrapper-array elements across all backends
# (needs fresh corelibs whose decoders place elements by id, not arrival order),
# so every sofab wire converges on one length; v0.12.0 emits allocation-light
# Java/C# code — thread-local encode scratch buffers, and C# native numeric/fp
# array fields become primitive T[] instead of List<T> (the csharp bench fill
# uses array syntax; pairs with the corelib-java/-cs hot-path releases); v0.13.0
# adds the typescript `int64: long` option (Long-backed 64-bit fields, used by
# languages/typescript/sofab/cfg.yaml); v0.14.0 tightens config validation — the
# config schema now lists ONLY honored options and rejects unknown keys hard
# (they were silently ignored before), so the cfg.yaml files had to drop stale
# no-op keys (generic.timestamp everywhere; the c target's string_storage /
# buffer / c_standard / descriptor_profile; python's package). Codegen is
# byte-identical to v0.13 across all targets — those keys already did nothing;
# v0.15.0 adds the Zig backend over corelib-zig (the max-speed Zig port —
# enables the zig maxspeed target; corelib-zig joins CORELIBS above); v0.15.2
# adds a fallible `try_decode` (Result-returning) alongside the infallible
# `decode` on the cpp/cpp-embedded/rust/rust-embedded backends, makes a
# fixed-capacity fill overflow on rust-embedded return Err(BufferFull) instead
# of a silently-truncated value (generator#82), and gives Java native numeric
# arrays bounded eager reservation (ARRAY_INIT_CAP) + ensureCap lazy growth.
# Wire byte-identical to v0.15.0 — gate stays 434B/494B; v0.15.3 lands the
# finish-less three-valued decode model from MESSAGE_SPEC §7 (generator#86): a
# one-shot decode now reports COMPLETE / INCOMPLETE (bytes end mid-field, NOT an
# error) / INVALID (malformed) instead of collapsing truncation into COMPLETE or
# INVALID, and the promoting finish()/finalize() step is gone. The C#/Java
# one-shot decoders — which previously discarded IStream.Feed/feed's
# DecodeStatus (generator#105, G-0008) — now surface the terminal status
# (tryDecode/TryDecode variants), so a truncated message is distinguishable from
# a COMPLETE one. Exception-based backends (Go/Rust/C++/C/Python/TS/Zig) already
# propagated INCOMPLETE. No wire or config-schema change — codegen for the full
# valid message is byte-identical, gate stays 434B/494B; v0.15.4 hardens the
# decoders to reject a scalar (native fixed-count) array whose declared element
# count exceeds the field's fixed capacity, in every backend (generator#100) —
# previously an over-count header could overrun/mis-decode; malformed input now
# fails as INVALID. Bug-fix only: the valid reference message is byte-identical,
# gate stays 434B/494B; v0.16.0 adds opt-in decode limits (generator#102/#109): a
# new `LimitExceeded` error category plus the go/py/ts limits APIs and
# corelib-cpp's `Limits{max_buffered_field}` + `exceedLimit()` hook, configured
# via the `generic: { max_dyn_array_count / max_dyn_string_len / max_dyn_blob_len }`
# keys. Wire-neutral: the arena sets no `max_dyn_*` keys, so codegen is
# byte-identical to v0.15.4 and the gate stays 434B/494B (the C#/Zig count-less
# native-array allocation hardening only affects schemas with count-less native
# arrays, which the arena message has none of); v0.16.1 is a C/C++/Go bounded-
# storage bug-fix release: Go omits an empty blob via len() instead of
# bytes.Equal (generator#113); the C/C++ fixed profile reserves char[maxlen+1]
# so a maxlen-length string keeps its NUL terminator (generator#103); a
# count-less native scalar array now lowers to std::vector instead of the
# degenerate std::array<T,0> (generator#112); and an unbounded field (no
# count/maxlen) is now a HARD generate-time error on the C/C++ backend
# (generator#104). The arena message is fully bounded (every scalar array is
# count:5, every string/blob carries a maxlen) so #104 never fires and no field
# gains/loses a NUL on the wire — codegen for the valid reference message stays
# byte-identical and the gate stays 434B/494B; v0.16.2 realigns the Zig emission
# with corelib-zig's finish-less decode: the generated decode() now binds the
# `feed(chunk)→Status` return and maps a truncated (INCOMPLETE) buffer to
# error.IncompleteMessage (generator#120/#121). Before v0.16.2 the Zig decode()
# dropped that Status value, which stopped compiling once corelib-zig main moved
# decode() from Error!void to Error!Status — this release is what lets the arena
# build Zig against the current corelib. Wire-neutral: the valid reference
# message still decodes to COMPLETE, codegen is byte-identical, gate stays
# 434B/494B; v0.17.0 renders all definition metadata as clean doc comments
# consistently across all 9 code backends (generator#123): field `deprecated`
# now lowers to each language's idiomatic marker plus a doc note, enum-const /
# flag `description` + flag `default` are emitted everywhere (previously only
# go/zig), and the boilerplate comments emitted into generated output are
# reworded free of internal issue refs. Comments/annotations only — wire output
# is byte-unchanged and all 9 conformance suites pass byte-exact, so the gate
# stays 434B/494B. The arena message carries only a message `summary` (no
# description/unit/deprecated/enums/flags), so the only committed-source delta
# is the comment rewording in the rust/cpp/zig backends (message.rs/example.hpp/
# message.zig regenerated + recommitted); csharp/java/python/ts/c/go codegen is
# byte-identical to v0.16.2; v0.17.1 is a C/C++ bounded-storage bug-fix release:
# the C++ fixed-capacity string/blob-sequence fill loop is now bounded so a
# malformed over-count header can no longer overrun the fixed buffer (DoS,
# generator#126/#127); the C backend now emits a *sized* blob (and sized
# blob-array elements) so a sub-maxlen blob round-trips its true length instead
# of being padded/mis-read to maxlen (generator#128/#129, #130/#131). These
# touch only the C/C++ backends and only affect blob/fixed-string handling; the
# valid reference message still encodes byte-identically (the gate stays
# 434B/494B) but the C/C++ generated sources are regenerated because the blob
# lowering changed. rust/zig/csharp/java/python/ts/go codegen is byte-identical
# to v0.17.0; v0.17.2 implements the MESSAGE_SPEC §3 trailing-default-run rule
# for `count: N` native arrays across all 9 backends (generator#137): encode now
# emits only [0, M'), M' being one past the last element differing from the
# ELEMENT default ([7,8,9] in a count:5 u32 lowers to `23 03 07 08 09`, no longer
# `23 05 07 08 09 00 00`), and decode always materializes exactly N (element
# defaults at [M, N)). Bit-pattern equality decides "is default", so a trailing
# -0.0 or NaN is never trimmed. The C backend gets the rule from the corelib, not
# from emitted code (its descriptor path has no used-length slot) — it needs
# corelib-c-cpp#87, which the version stamp below pulls in via fresh clones;
# v0.17.3 fixes a go-only v0.17.2 regression (generator#140): go's marshal
# omit-guard compared a growable []T against the now-N-element-padded default, so
# an all-default count:N array was emitted as an explicit empty array instead of
# being omitted per §2 — it now compares trimmed value against trimmed default.
# WIRE-NEUTRAL FOR THIS ARENA, and not by luck: the trim only shortens an array
# whose TRAILING elements are the element default, and every count:5 array in
# schema/state.json deliberately ends on a non-default extreme (255, 127, 65535,
# u64::MAX, ±3.4e38, ±1.79e308 ...), so M' == 5 for all ten of them and nothing
# is trimmed. The gate stays 434B/494B — but if the payload ever grows an array
# with a trailing zero, THIS bump is what will move the sofab wire, and all four
# reference sync points must move with it.
# Bump together with whatever generated-code contract the targets rely on.
SOFABGEN_VERSION="${SOFABGEN_VERSION:-v0.17.3}"

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
