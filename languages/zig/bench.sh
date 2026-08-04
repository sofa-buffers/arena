#!/usr/bin/env bash
# Zig target: run every impl, print one BENCH line each to stdout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BENCH_ITERS="${BENCH_ITERS:-2000000}"

# Buffer the streaming impls render through, well below the ~434/494 B message so
# the drain path is exercised. ONE value for both sides of the streaming row: it
# compares codecs, not harness granularity (#108).
export STREAM_BUF_BYTES="${STREAM_BUF_BYTES:-64}"

# Same binaries, run once per impl: BENCH_IMPL selects the encode path inside each
# bench, so both impls of a pair come from one build.
BENCH_IMPL=sofab           "$HERE/sofab/gen/zig-out/bin/bench"
BENCH_IMPL=protobuf        "$HERE/protobuf/zig-out/bin/bench"
BENCH_IMPL=sofab-stream    "$HERE/sofab/gen/zig-out/bin/bench"
BENCH_IMPL=protobuf-stream "$HERE/protobuf/zig-out/bin/bench"
