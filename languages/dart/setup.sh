#!/usr/bin/env bash
# Dart target setup: generate the sofab project (corelib-dart) + the protobuf
# bindings (protoc-gen-dart), then AOT-compile BOTH to native executables with
# the identical `dart compile exe` toolchain. Idempotent.
#
# Both impls run AOT-native — never `dart run`/JIT — the fair comparison to the
# compiled ports (C/C++/Rust/Go), which also run native. Identical compile
# invocation for both = the fairness core (docs/BENCH.md).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="${SOFAB_DART_CORELIB:-$ROOT/vendor/corelib-dart}"

# Dart SDK + the shared pub cache holding protoc-gen-dart (Dockerfile bakes both
# onto PATH/PUB_CACHE; re-assert defensively so a bare shell also works).
export PUB_CACHE="${PUB_CACHE:-/usr/local/pub-cache}"
export PATH="/usr/local/dart-sdk/bin:$PUB_CACHE/bin:$PATH"

########################################################################
# 1. SofaBuffers: generate the typed message project against corelib-dart.
########################################################################
# `emit: project` writes a self-contained Dart package (module `harness`) into
# sofab/gen/: pubspec.yaml, lib/message.dart, bin/harness.dart, README.md.
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang dart \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >/dev/null

# Wire corelib-dart via the pubspec placeholder (idempotent: no-op once replaced).
sed -i "s#\${SOFAB_DART_CORELIB}#$CORELIB#" "$HERE/sofab/gen/pubspec.yaml"

# Drop our AOT bench driver + the shared support (CpuClock + gate SHA-256) in
# beside the generated harness. Sources live in sofab/bench.dart and common/;
# the copies under gen/bin are gitignored (regenerated here every run).
cp "$HERE/sofab/bench.dart"          "$HERE/sofab/gen/bin/bench.dart"
cp "$HERE/common/bench_common.dart"  "$HERE/sofab/gen/bin/bench_common.dart"

# Resolve from the image's shared PUB_CACHE and never from the network: a bench
# run must not depend on pub.dev being reachable. `dart pub get` has no deadline
# and no retry message — a single dropped request leaves it sitting in
# "Resolving dependencies..." indefinitely, which stalls the WHOLE arena at
# `--- setup (dart) ---` with nothing in results/raw/dart.setup.log to say where.
# (The runner caps every setup.sh now, so such a stall can no longer run forever
# — but a target that needs no network at all cannot stall in the first place.)
# Offline is also the honest state of this target: this project's only dependency
# is the corelib path above, and the protobuf row's protobuf+fixnum are already
# in the cache because the Dockerfile activates protoc_plugin, whose own pubspec
# pins them — the version-pairing invariant protobuf/pubspec.yaml documents.
# The online fallback only covers the window after a dependency bump and before
# the image is rebuilt (same `A || B` idiom as languages/typescript/setup.sh);
# stdout stays in the setup log so a stall there is visible, not silent.
( cd "$HERE/sofab/gen" \
    && { dart pub get --offline || dart pub get; } \
    && dart compile exe bin/bench.dart -o bin/bench >/dev/null )

########################################################################
# 2. Protobuf: generate message.pb.dart with protoc-gen-dart, AOT-compile.
########################################################################
mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" --dart_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"

# Shared support next to the protobuf driver (identical helper as the sofab row).
cp "$HERE/common/bench_common.dart" "$HERE/protobuf/bench_common.dart"

# Cache-first like the sofab row above (same reasoning). This is the resolution
# that actually goes online when it cannot: `pubspec.lock` and `.dart_tool/` are
# gitignored, so a fresh clone (or `git clean -xfd`) has nothing to short-circuit
# on and pub re-resolves from scratch — the one dart setup that a flaky network
# could hang, every time, on a clean checkout.
( cd "$HERE/protobuf" \
    && { dart pub get --offline || dart pub get; } \
    && dart compile exe bench.dart -o bench >/dev/null )

echo "dart: setup OK" >&2
