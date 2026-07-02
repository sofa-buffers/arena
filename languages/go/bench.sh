#!/usr/bin/env bash
# Go target: run both impls, print BENCH lines to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export STATE_JSON="${STATE_JSON:-$ROOT/schema/state.json}"
export BENCH_ITERS="${BENCH_ITERS:-1000000}"
export PATH="$(go env GOPATH)/bin:$PATH"

# Portable runtime tuning for this single-threaded microbench (applied to BOTH
# impls so the comparison stays fair). No CPU/ISA pinning -> runs on any host.
#   GOGC=400     ~4x less-frequent GC (bench allocs a buffer per iter; GOGC=off OOMs).
#   GOMAXPROCS=1 single OS thread -> no cross-P GC-assist/scheduler overhead.
export GOGC="${GOGC:-400}"
export GOMAXPROCS="${GOMAXPROCS:-1}"

( cd "$HERE/sofab"    && GOFLAGS=-mod=mod go run . )
( cd "$HERE/protobuf" && GOFLAGS=-mod=mod go run . )
