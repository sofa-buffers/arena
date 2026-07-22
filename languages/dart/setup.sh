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

( cd "$HERE/sofab/gen" \
    && dart pub get >/dev/null \
    && dart compile exe bin/bench.dart -o bin/bench >/dev/null )

########################################################################
# 2. Protobuf: generate message.pb.dart with protoc-gen-dart, AOT-compile.
########################################################################
mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" --dart_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"

# Shared support next to the protobuf driver (identical helper as the sofab row).
cp "$HERE/common/bench_common.dart" "$HERE/protobuf/bench_common.dart"

( cd "$HERE/protobuf" \
    && dart pub get >/dev/null \
    && dart compile exe bench.dart -o bench >/dev/null )

echo "dart: setup OK" >&2
