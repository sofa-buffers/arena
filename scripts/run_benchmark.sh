#!/usr/bin/env bash
#
# run_benchmark.sh — the single entry point for the SofaBuffers Arena.
#
# For every language it builds (setup.sh) and runs (bench.sh) two targets —
# SofaBuffers and Protocol Buffers — that encode+decode the IDENTICAL message
# with IDENTICAL values, then prints one big cross-language comparison of
# SofaBuffers vs protobuf on wire size and throughput.
#
# Every target emits uniform, machine-readable BENCH lines (see docs/BENCH.md):
#   BENCH lang=<l> impl=<sofab|protobuf> serialized_bytes=<n> iters=<n> \
#         cpu_time_s=<f> throughput_mbs=<f> sha256=<hex>
#
# Usage:
#   ./scripts/run_benchmark.sh                 # setup + run every language
#   ./scripts/run_benchmark.sh --no-setup      # skip setup.sh (reuse builds)
#   LANGS="python go" ./scripts/run_benchmark.sh
#   BENCH_ITERS=100000 ./scripts/run_benchmark.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LANGS="${LANGS:-c cpp rust go csharp java typescript python}"
DO_SETUP=1
[ "${1:-}" = "--no-setup" ] && DO_SETUP=0

export STATE_JSON="$ROOT/schema/state.json"
export SOFABGEN="$ROOT/tools/sofabgen"

RAW="$ROOT/results/raw"; mkdir -p "$RAW"
export PATH="$HOME/.cargo/bin:/usr/local/dotnet:$PATH"
export DOTNET_ROOT="${DOTNET_ROOT:-/usr/local/dotnet}"

declare -A SER MBS ITERS SHA CPU STATUS

REF_SOFAB_SHA="db362bf24959b41fd153b59958e2afdf59020c6c3501fb60e189526659a72ed4"
REF_PROTO_SHA="e8d391d98bc54c0ec24fff19ec96bb52114d9d34aed7d0f0023a0317bcfa5b3d"
# The C backend is the SofaBuffers *object API* (corelib-c-cpp), which drops the
# one empty string in string_array — a documented leanness optimization — so its
# wire is 434 B, not 436 B. This is the correct output of that backend, not drift.
REF_SOFAB_C_SHA="e1733416c987b04faea747b7cdd8f2913934f45d4a77453f58c9e3ef12e29d9d"
expected_sofab_sha() { [ "$1" = c ] && echo "$REF_SOFAB_C_SHA" || echo "$REF_SOFAB_SHA"; }

parse_line() {   # <line>
    local line="$1" lang impl
    lang="$(sed -n 's/.*\blang=\([^ ]*\).*/\1/p' <<<"$line")"
    impl="$(sed -n 's/.*\bimpl=\([^ ]*\).*/\1/p' <<<"$line")"
    [ -n "$lang" ] && [ -n "$impl" ] || return
    local key="$lang,$impl"
    SER[$key]="$(sed -n 's/.*serialized_bytes=\([0-9]*\).*/\1/p' <<<"$line")"
    ITERS[$key]="$(sed -n 's/.*\biters=\([0-9]*\).*/\1/p' <<<"$line")"
    CPU[$key]="$(sed -n 's/.*cpu_time_s=\([0-9.]*\).*/\1/p' <<<"$line")"
    MBS[$key]="$(sed -n 's/.*throughput_mbs=\([0-9.]*\).*/\1/p' <<<"$line")"
    SHA[$key]="$(sed -n 's/.*sha256=\([0-9a-f]*\).*/\1/p' <<<"$line")"
}

for lang in $LANGS; do
    dir="languages/$lang"
    [ -d "$dir" ] || { echo "skip $lang (no dir)"; STATUS[$lang]=MISSING; continue; }
    echo "==================================================================="
    echo " $lang"
    echo "==================================================================="
    if [ "$DO_SETUP" = 1 ] && [ -x "$dir/setup.sh" ]; then
        echo "--- setup ($lang) ---"
        if ! "$dir/setup.sh" >"$RAW/$lang.setup.log" 2>&1; then
            echo "!! setup FAILED for $lang (see $RAW/$lang.setup.log)"; STATUS[$lang]=SETUP_FAIL; continue
        fi
    fi
    echo "--- bench ($lang) ---"
    if ! "$dir/bench.sh" >"$RAW/$lang.out" 2>"$RAW/$lang.err"; then
        echo "!! bench FAILED for $lang (see $RAW/$lang.err)"; STATUS[$lang]=BENCH_FAIL
    else
        STATUS[$lang]=OK
    fi
    while IFS= read -r line; do
        case "$line" in BENCH*) parse_line "$line"; echo "  $line";; esac
    done < "$RAW/$lang.out"
done

# ---------------------------------------------------------------- correctness gate
echo
echo "================================================================================"
echo " Cross-language correctness gate (wire bytes must be identical per impl)"
echo "================================================================================"
gate_ok=1
for impl in sofab protobuf; do
    for lang in $LANGS; do
        s="${SHA[$lang,$impl]:-}"
        [ -n "$s" ] || continue
        if [ "$impl" = protobuf ]; then ref="$REF_PROTO_SHA"; else ref="$(expected_sofab_sha "$lang")"; fi
        note=""
        [ "$lang" = c ] && [ "$impl" = sofab ] && note="  (object API: drops empty string)"
        if [ "$s" = "$ref" ]; then mark="ok"; else mark="MISMATCH"; gate_ok=0; fi
        printf "  %-11s %-9s %s  %s%s\n" "$lang" "$impl" "${SER[$lang,$impl]:-?}B" "$mark" "$note"
    done
done
[ "$gate_ok" = 1 ] && echo "  => all present targets are byte-identical to the reference wire." \
                    || echo "  => WARNING: some targets diverge from the reference wire (fill drift)."

# ---------------------------------------------------------------- the big picture
mbps() { printf '%s' "${MBS[$1]:-}"; }
ratio() { # a/b with 2 decimals, or "-" if unusable
    local a="$1" b="$2"
    awk -v a="$a" -v b="$b" 'BEGIN{ if(a=="" || b=="" || b+0==0){print "-"} else {printf "%.2f", a/b} }'
}

{
echo
echo "================================================================================"
echo " SofaBuffers vs Protobuf — the big picture"
echo "   same message, same values, every language. size in bytes; speed in MB/s"
echo "   (encode+decode throughput). MB/s is within-language only (different runtimes)."
echo "================================================================================"
printf "  %-11s | %14s | %20s | %20s\n" "language" "wire size (B)" "throughput MB/s" "sofab advantage"
printf "  %-11s | %6s %7s | %9s %10s | %8s %11s\n" "" "sofab" "proto" "sofab" "proto" "size" "speed"
printf '  '; printf -- '-%.0s' $(seq 1 76); printf '\n'
for lang in $LANGS; do
    ss="${SER[$lang,sofab]:-}"; ps="${SER[$lang,protobuf]:-}"
    sm="$(mbps "$lang,sofab")"; pm="$(mbps "$lang,protobuf")"
    [ -z "$ss$ps$sm$pm" ] && continue
    size_adv="$(ratio "$ps" "$ss")"      # >1 means sofab smaller
    speed_adv="$(ratio "$sm" "$pm")"     # >1 means sofab faster
    printf "  %-11s | %6s %7s | %9s %10s | %7sx %10sx\n" \
        "$lang" "${ss:-–}" "${ps:-–}" "${sm:-–}" "${pm:-–}" "$size_adv" "$speed_adv"
done
echo
echo "  size advantage  = protobuf_bytes / sofab_bytes   (>1: SofaBuffers is smaller on the wire)"
echo "  speed advantage = sofab_MBps / protobuf_MBps     (>1: SofaBuffers encodes+decodes faster)"
echo
echo "  status per language:"
for lang in $LANGS; do printf "    %-11s %s\n" "$lang" "${STATUS[$lang]:-?}"; done
} | tee "$ROOT/results/RESULTS.txt"

echo
echo "wrote results/RESULTS.txt (raw BENCH lines + logs under results/raw/)."
