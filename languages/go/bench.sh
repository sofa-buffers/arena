#!/usr/bin/env bash
# Go target: run both impls, print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-1000000}"
export PATH="$(go env GOPATH)/bin:$PATH"

( cd "$HERE/sofab"    && GOFLAGS=-mod=mod go run . )
( cd "$HERE/protobuf" && GOFLAGS=-mod=mod go run . )
