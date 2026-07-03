#!/usr/bin/env bash
# Go target setup: generate sofab (corelib-go) + protobuf (protoc-gen-go)
# bindings and build both. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOFABGEN="${SOFABGEN:-$ROOT/tools/sofabgen}"
CORELIB="${SOFAB_GO_CORELIB:-$ROOT/vendor/corelib-go}"

# Make go-installed tools (protoc-gen-go) visible to protoc.
export PATH="$(go env GOPATH)/bin:$PATH"

########################################################################
# 1. SofaBuffers: generate the typed message project against corelib-go.
########################################################################
# The generator emits a self-contained Go module (module example.com/gen)
# directly into sofab/: go.mod, message/, harness/, README.md. Our own
# main.go in sofab/ is additive and is never overwritten.
"$SOFABGEN" --config "$HERE/sofab/cfg.yaml" --lang go \
    --in "$ROOT/schema/message.sofab.yaml" --out "$HERE/sofab" >/dev/null

# The generated types.go references bytes.Equal for the blob field but omits
# the "bytes" import; add it if missing (idempotent).
if ! grep -q '"bytes"' "$HERE/sofab/message/types.go"; then
    sed -i 's#^\t"github.com/sofa-buffers/corelib-go"#\t"bytes"\n\t"github.com/sofa-buffers/corelib-go"#' \
        "$HERE/sofab/message/types.go"
fi

# Perf: re-apply the visitor decode. sofabgen emits a pull-based unmarshal that
# reads every varint byte through bufio.ReadByte and make()s a buffer per float;
# this patch decodes via the corelib's zero-copy AcceptBytes cursor instead (see
# docs/perf/bottlenecks.md). Generator-spec patch — fold into codegen upstream.
# Idempotent (marker-guarded), applied after the bytes-import fixup above.
if ! grep -q "AcceptBytes" "$HERE/sofab/message/example.go"; then
    patch -p1 -d "$HERE/sofab/message" < "$HERE/sofab/decode-visitor.patch" >&2
fi

# Wire corelib-go via the go.mod placeholder (idempotent: no-op once replaced).
sed -i "s#\${SOFAB_GO_CORELIB}#$CORELIB#" "$HERE/sofab/go.mod"

( cd "$HERE/sofab" && GOFLAGS=-mod=mod go mod tidy >/dev/null 2>&1 && go build ./... )

########################################################################
# 2. Protobuf: generate message.pb.go with protoc-gen-go, build.
########################################################################
if ! command -v protoc-gen-go >/dev/null 2>&1; then
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
fi

mkdir -p "$HERE/protobuf/gen"
protoc -I "$ROOT/schema" \
    --go_out="$HERE/protobuf/gen" --go_opt=paths=source_relative \
    --go_opt=Mmessage.proto=example.com/pbbench/gen \
    "$ROOT/schema/message.proto"

# Self-contained module. protobuf-go >= v1.36 needs a >= 1.23 toolchain;
# go1.25.11 is what `go install ...@latest` pulls in this environment.
cat > "$HERE/protobuf/go.mod" <<'EOF'
module example.com/pbbench

go 1.23

toolchain go1.25.11
EOF
( cd "$HERE/protobuf" && GOFLAGS=-mod=mod go mod tidy >/dev/null 2>&1 && go build ./... )

echo "go: setup OK" >&2
