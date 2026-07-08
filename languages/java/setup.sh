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

# sofabgen's Java template pins older tool/dep versions than the arena tracks.
# Renovate bumps them in the committed (generated) pom.xml, but regenerating it
# above would silently revert those merged bumps and leave a dirty tree. Until
# the bumps land in a sofabgen release, re-apply the arena-pinned versions here
# so setup stays idempotent (same pattern as typescript/setup.sh reconciling its
# generated package.json). Keep these in sync with Renovate / protobuf/pom.xml.
POM="$HERE/sofab/gen/pom.xml"
sed -i \
    -e 's#\(<artifactId>gson</artifactId><version>\)[^<]*#\12.14.0#' \
    -e '/<artifactId>maven-assembly-plugin<\/artifactId>/{n;s#<version>[^<]*</version>#<version>3.8.0</version>#;}' \
    "$POM"

cp "$HERE/sofab/Bench.java" "$HERE/sofab/gen/src/main/java/message/Bench.java"
( cd "$HERE/sofab/gen" && mvn -q -Dsofab.version="$VER" package )

# (3) protobuf: generate Java bindings from the .proto, build the bench project
#     (protobuf-java dependency) into a self-contained harness jar.
mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" --java_out="$HERE/protobuf/gen" "$ROOT/schema/message.proto"
( cd "$HERE/protobuf" && mvn -q package )

echo "java: setup OK" >&2
