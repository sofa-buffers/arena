#!/usr/bin/env bash
# Go target: run both impls, print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../common/cooldown.sh"   # cooldown_between_impls (COOLDOWN_S from the runner)
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-1000000}"
export PATH="$(go env GOPATH)/bin:$PATH"

# Default GC. GOMAXPROCS=1 (both impls) keeps the bench on one thread, so the
# process CPU time it reports is the loop's own, not parallel GC workers'.
export GOMAXPROCS="${GOMAXPROCS:-1}"

( cd "$HERE/sofab"    && GOFLAGS=-mod=mod go run . )
cooldown_between_impls
( cd "$HERE/protobuf" && GOFLAGS=-mod=mod go run . )
