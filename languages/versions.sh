# Central third-party version pins for GENERATED build files.
#
# Why this file exists
# --------------------
# Several targets commit *generated* manifests (the `sofab/gen/` and the
# heredoc-written `go/protobuf/go.mod`). Their versions are produced by
# `setup.sh` / sofabgen — so `setup.sh` is the single source of truth for them,
# and `.github/renovate.json` lists those paths under `ignorePaths` so Renovate
# never bumps an artifact that the next `setup.sh` run would just revert (that
# reversion was the "dependency drift" this file removes).
#
# Each `setup.sh` sources this file and forces these versions into the file it
# generates, so a re-run is idempotent (clean git tree) and — for deps that also
# appear on the hand-written protobuf/micropb side of the same row — the two
# impls stay in lockstep (the fairness core: identical deps per row).
#
# SYNC POINT: the values below that are shared with a hand-written manifest are
# duplicated there and MUST be bumped together (Renovate still maintains the
# hand-written side for security):
#   JAVA_MAVEN_COMPILER_PLUGIN / _ASSEMBLY_PLUGIN <-> languages/java/protobuf/pom.xml
#   RUST_SHA2                                     <-> languages/rust/protobuf/Cargo.toml
#   RUST_HEAPLESS / RUST_SHA2                     <-> languages/rust-embedded/micropb*/Cargo.toml
#   TS_TYPES_NODE / TS_TYPESCRIPT / TS_TSX        <-> languages/typescript/protobuf/package.json
# Bump here deliberately, keep the paired manifest in step, re-run the target's
# setup.sh (tree must stay clean), then refresh results with a full RUNS=5.

# --- Go ---------------------------------------------------------------------
# The protobuf harness's go.mod is written by go/setup.sh. protobuf-go >= v1.36
# needs a >= 1.23 toolchain; pin the toolchain that `go install ...@latest`
# actually resolves in this environment (Renovate had drifted this to a version
# the container does not ship).
GO_TOOLCHAIN=go1.25.11

# --- Rust (host + embedded sofab crates) ------------------------------------
RUST_SHA2=0.11
# micropb 0.6 wires its container impls to heapless 0.8 (container-heapless-0-8);
# 0.9 drops them and the no_std codec fails to compile. Keep the sofab crate in
# lockstep with the micropb baseline on 0.8.
RUST_HEAPLESS=0.8

# --- Java (sofabgen template pins older than the arena tracks) --------------
JAVA_MAVEN_COMPILER_PLUGIN=3.15.0
JAVA_MAVEN_ASSEMBLY_PLUGIN=3.8.0
JAVA_GSON=2.14.0

# --- TypeScript (sofabgen template devDeps) ---------------------------------
TS_TYPES_NODE=^26.1.1
TS_TYPESCRIPT=^6.0.3
TS_TSX=^4.23.1
