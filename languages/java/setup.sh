#!/usr/bin/env bash
# Java target setup: build corelib-java, generate + build sofab and protobuf
# maven harnesses. Idempotent; exits 0 on success.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="$ROOT/vendor/corelib-java"

# corelib-java version (drives the -Dsofab.version the generated pom expects).
VER="$(grep -m1 '<version>' "$CORELIB/pom.xml" | sed 's/.*<version>\(.*\)<\/version>.*/\1/')"

# (1) Install corelib-java to the local maven repo.
( cd "$CORELIB" && mvn -q -DskipTests install )

# (2) sofab: generate the typed message project, drop in the bench driver
#     (package `message`, so it can call the generated Json.from helper), build.
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang java \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab/gen" >/dev/null
cp "$HERE/sofab/Bench.java" "$HERE/sofab/gen/src/main/java/message/Bench.java"
( cd "$HERE/sofab/gen" && mvn -q -Dsofab.version="$VER" package )

# (3) protobuf: generate Java bindings from the .proto, build the bench project
#     (protobuf-java dependency) into a self-contained harness jar.
mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" --java_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"
( cd "$HERE/protobuf" && mvn -q package )

echo "java: setup OK" >&2
