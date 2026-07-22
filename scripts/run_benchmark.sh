#!/usr/bin/env bash
#
# run_benchmark.sh — the single entry point for the SofaBuffers Arena.
#
# For every language it builds (setup.sh) and runs (bench.sh) a SofaBuffers
# target and one or more baseline serialization targets that encode+decode the
# IDENTICAL message with IDENTICAL values, then prints a cross-language
# comparison split into two categories:
#
#   maxspeed  — ranked by encode+decode THROUGHPUT (MB/s). SofaBuffers corelib
#               vs the mature Google protobuf runtime for that language.
#   embedded  — ranked by isolated codec FOOTPRINT (.text/.rodata/RAM, bytes).
#               SofaBuffers embedded corelib vs footprint-oriented protobuf
#               libraries (nanopb, EmbeddedProto, micropb, ...).
#
# A target's category is declared in `languages/<lang>/meta`:
#   category=embedded|maxspeed   (default maxspeed)
#   metric=footprint|throughput  (default throughput)
#
# Every target emits uniform, machine-readable lines on stdout (docs/BENCH.md):
#   BENCH     lang=<l> impl=<i> serialized_bytes=<n> iters=<n> \
#             cpu_time_s=<f> throughput_mbs=<f> sha256=<hex>
#   FOOTPRINT lang=<l> impl=<i> text=<n> rodata=<n> data=<n> bss=<n>
# (maxspeed targets emit BENCH only; host embedded targets emit both — their
# throughput gets its own maxspeed-style table; bare-metal embedded targets are
# build-only and emit FOOTPRINT only.)
#
# Usage:
#   ./scripts/run_benchmark.sh                 # setup + run every language
#   ./scripts/run_benchmark.sh --no-setup      # skip setup.sh (reuse builds)
#   LANGS="python go" ./scripts/run_benchmark.sh
#   BENCH_ITERS=100000 ./scripts/run_benchmark.sh
#   RUNS=5 ./scripts/run_benchmark.sh                # best-of-5 throughput (noise)
#
# The cross-language correctness gate is fatal: if any present impl's wire bytes
# diverge from the shared reference (sofab 434 B / proto 494 B) the run exits
# non-zero before reporting, so drifted numbers never reach results/RESULTS.txt.
# Set ALLOW_WIRE_MISMATCH=1 to downgrade the gate to a warning for local iteration.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LANGS="${LANGS:-c-embedded cpp rust zig dart go csharp java typescript typescript-bun python rust-embedded cpp-embedded c-cortex-m cpp-cortex-m rust-cortex-m c-riscv cpp-riscv rust-riscv}"
DO_SETUP=1
[ "${1:-}" = "--no-setup" ] && DO_SETUP=0
# Throughput is noisy; RUNS repeats each bench and keeps the BEST (max) MB/s per
# impl (noise is downward). Footprint is deterministic. Default 5 (best-of-5, the
# reported metric); set RUNS=1 for a quick single run while iterating.
RUNS="${RUNS:-5}"

export STATE_JSON="$ROOT/schema/state.json"
export SOFABGEN="$ROOT/tools/sofabgen"

RAW="$ROOT/results/raw"; mkdir -p "$RAW"
export PATH="$HOME/.cargo/bin:/usr/local/cargo/bin:/usr/local/dotnet:$PATH"
export DOTNET_ROOT="${DOTNET_ROOT:-/usr/local/dotnet}"

declare -A SER MBS ITERS SHA CPU STATUS CODEC
declare -A TEXT RODATA DATA BSS         # footprint sections (embedded targets)
declare -A CATEGORY METRIC              # per-language, from languages/<lang>/meta
declare -A IMPLS                        # lang -> space-separated impls seen

# Since sofabgen v0.11.0 every backend sparsely omits a wrapper-array element that
# equals its default (here the one empty string in string_array), so all impl=sofab
# targets — the C object API (corelib-c-cpp), its C++ wrapper, and every other
# corelib that previously encoded that element positionally — now converge on one
# 434-byte wire. (Before v0.11.0 only the C object API omitted it; others were 436 B.)
REF_SOFAB_SHA="e1733416c987b04faea747b7cdd8f2913934f45d4a77453f58c9e3ef12e29d9d"
REF_PROTO_SHA="e8d391d98bc54c0ec24fff19ec96bb52114d9d34aed7d0f0023a0317bcfa5b3d"
expected_sofab_sha() { echo "$REF_SOFAB_SHA"; }
# Every non-sofab impl (protobuf, protobuf-c, nanopb, ...) must match the proto wire.
expected_sha() { [ "$2" = sofab ] && expected_sofab_sha "$1" || echo "$REF_PROTO_SHA"; }

field() { sed -n "s/.*\b$2=\([^ ]*\).*/\1/p" <<<"$1"; }   # <line> <key>

register_impl() {   # <lang> <impl>
    local lang="$1" impl="$2"
    case " ${IMPLS[$lang]:-} " in *" $impl "*) ;; *) IMPLS[$lang]="${IMPLS[$lang]:-} $impl";; esac
}

parse_line() {   # <line>
    local line="$1" lang impl key
    lang="$(field "$line" lang)"; impl="$(field "$line" impl)"
    [ -n "$lang" ] && [ -n "$impl" ] || return
    key="$lang,$impl"; register_impl "$lang" "$impl"
    case "$line" in
        BENCH*)
            SER[$key]="$(field "$line" serialized_bytes)"
            SHA[$key]="$(field "$line" sha256)"
            local cd; cd="$(field "$line" codec)"; [ -n "$cd" ] && CODEC[$key]="$cd"
            local m; m="$(field "$line" throughput_mbs)"
            # best-of-N: keep the max throughput seen across repeated runs
            if [ -z "${MBS[$key]:-}" ] || awk -v a="$m" -v b="${MBS[$key]}" 'BEGIN{exit !(a+0>b+0)}'; then
                MBS[$key]="$m"; CPU[$key]="$(field "$line" cpu_time_s)"; ITERS[$key]="$(field "$line" iters)"
            fi
            ;;
        FOOTPRINT*)
            TEXT[$key]="$(field "$line" text)"
            RODATA[$key]="$(field "$line" rodata)"
            DATA[$key]="$(field "$line" data)"
            BSS[$key]="$(field "$line" bss)"
            ;;
    esac
}

# impls for a lang, sofab first
ordered_impls() {   # <lang>
    local lang="$1" i
    case " ${IMPLS[$lang]:-} " in *" sofab "*) printf 'sofab ';; esac
    for i in ${IMPLS[$lang]:-}; do [ "$i" = sofab ] || printf '%s ' "$i"; done
}

for lang in $LANGS; do
    dir="languages/$lang"
    [ -d "$dir" ] || { echo "skip $lang (no dir)"; STATUS[$lang]=MISSING; continue; }
    CATEGORY[$lang]="$(sed -n 's/^category=//p' "$dir/meta" 2>/dev/null)"; CATEGORY[$lang]="${CATEGORY[$lang]:-maxspeed}"
    METRIC[$lang]="$(sed -n 's/^metric=//p' "$dir/meta" 2>/dev/null)"; METRIC[$lang]="${METRIC[$lang]:-throughput}"
    echo "==================================================================="
    echo " $lang  [${CATEGORY[$lang]}]"
    echo "==================================================================="
    if [ "$DO_SETUP" = 1 ] && [ -x "$dir/setup.sh" ]; then
        echo "--- setup ($lang) ---"
        if ! "$dir/setup.sh" >"$RAW/$lang.setup.log" 2>&1; then
            echo "!! setup FAILED for $lang (see $RAW/$lang.setup.log)"; STATUS[$lang]=SETUP_FAIL; continue
        fi
    fi
    echo "--- bench ($lang)$([ "$RUNS" -gt 1 ] && echo " x$RUNS best-of") ---"
    : > "$RAW/$lang.out"; : > "$RAW/$lang.err"; bok=1
    for _r in $(seq 1 "$RUNS"); do
        "$dir/bench.sh" >>"$RAW/$lang.out" 2>>"$RAW/$lang.err" || bok=0
    done
    if [ "$bok" = 1 ]; then STATUS[$lang]=OK; else echo "!! bench FAILED for $lang (see $RAW/$lang.err)"; STATUS[$lang]=BENCH_FAIL; fi
    while IFS= read -r line; do
        case "$line" in BENCH*|FOOTPRINT*) parse_line "$line";; esac
    done < "$RAW/$lang.out"
done

# ---------------------------------------------------------------- correctness gate
echo
echo "================================================================================"
echo " Cross-language correctness gate (wire bytes must be identical per impl)"
echo "================================================================================"
gate_ok=1
for lang in $LANGS; do
    for impl in $(ordered_impls "$lang"); do
        s="${SHA[$lang,$impl]:-}"; [ -n "$s" ] || continue
        ref="$(expected_sha "$lang" "$impl")"
        if [ "$s" = "$ref" ]; then mark="ok"; else mark="MISMATCH"; gate_ok=0; fi
        printf "  %-14s %-13s %s  %s\n" "$lang" "$impl" "${SER[$lang,$impl]:-?}B" "$mark"
    done
done
if [ "$gate_ok" = 1 ]; then
    echo "  => all present targets are byte-identical to the reference wire."
elif [ -n "${ALLOW_WIRE_MISMATCH:-}" ]; then
    echo "  => WARNING: some targets diverge from the reference wire (fill/codegen drift)."
    echo "     ALLOW_WIRE_MISMATCH set — continuing despite the mismatch (results are NOT apples-to-apples)."
else
    # A MISMATCH means a present impl encodes a different wire than the shared
    # reference, so its throughput/footprint is measured on the wrong bytes and the
    # cross-impl comparison is no longer fair — the whole point of the arena. Fail
    # loudly instead of burying it in a warning, and do NOT reach the reporting
    # block below, so a good results/RESULTS.txt is not overwritten with drifted
    # numbers. For an intentional wire change, update the four reference sync points
    # (REF_*_SHA here, docs/BENCH.md, schema/STATE.md, the README) — see docs/BENCH.md.
    echo "  => FAIL: some targets diverge from the reference wire (fill/codegen drift)." >&2
    echo "     Each MISMATCH above encodes a different wire than the shared reference." >&2
    echo "     Fix the drifting target, or set ALLOW_WIRE_MISMATCH=1 to override locally." >&2
    exit 1
fi

# ---------------------------------------------------------------- reporting helpers
mbps() { printf '%s' "${MBS[$1]:-}"; }
# msgs/s = iters / cpu_time_s — messages processed per second, derived from the
# BENCH fields already captured (no target emits it; #85). Unlike MB/s it does not
# scale by wire size, so it is the size-neutral per-message codec speed: MB/s
# credits SofaBuffers' smaller wire, msgs/s does not. Uses the best run's CPU/ITERS
# (kept in lockstep with MBS above, so it matches the reported MB/s).
msgs_s() { # <key> -> integer msgs/s, or "" if unusable
    awk -v it="${ITERS[$1]:-}" -v t="${CPU[$1]:-}" \
        'BEGIN{ if(it=="" || t=="" || t+0==0){print ""} else {printf "%d", it/t} }'
}
ratio() { # a/b with 2 decimals, or "-" if unusable
    awk -v a="$1" -v b="$2" 'BEGIN{ if(a=="" || b=="" || b+0==0){print "-"} else {printf "%.2f", a/b} }'
}
langs_in() { # <category> — langs of that category, in LANGS order, that produced data
    local want="$1" lang
    for lang in $LANGS; do [ "${CATEGORY[$lang]:-maxspeed}" = "$want" ] && [ -n "${IMPLS[$lang]:-}" ] && printf '%s ' "$lang"; done
}

{
# ============================ maxspeed: throughput ============================
maxspeed_langs="$(langs_in maxspeed)"
if [ -n "$maxspeed_langs" ]; then
echo
echo "================================================================================"
echo " MAXSPEED — SofaBuffers vs Protobuf, encode+decode throughput"
echo "   same message, same values. size in bytes; MB/s = bytes/s, msgs/s = messages/s"
echo "   (both higher is better). MB/s counts bytes moved, so it credits SofaBuffers'"
echo "   smaller wire; msgs/s counts messages, the size-neutral per-message codec speed."
echo "   Both are within-language only (different runtimes) — never compare rows."
echo "================================================================================"
printf "  %-11s | %14s | %20s | %20s | %23s\n" "language" "wire size (B)" "throughput MB/s" "throughput msgs/s" "sofab advantage"
printf "  %-11s | %6s %7s | %9s %10s | %9s %10s | %7s %7s %7s\n" "" "sofab" "proto" "sofab" "proto" "sofab" "proto" "size" "MB/s" "msg/s"
printf '  '; printf -- '-%.0s' $(seq 1 100); printf '\n'
for lang in $maxspeed_langs; do
    ss="${SER[$lang,sofab]:-}"; ps="${SER[$lang,protobuf]:-}"
    sm="$(mbps "$lang,sofab")"; pm="$(mbps "$lang,protobuf")"
    sM="$(msgs_s "$lang,sofab")"; pM="$(msgs_s "$lang,protobuf")"
    [ -z "$ss$ps$sm$pm" ] && continue
    printf "  %-11s | %6s %7s | %9s %10s | %9s %10s | %6sx %6sx %6sx\n" \
        "$lang" "${ss:-–}" "${ps:-–}" "${sm:-–}" "${pm:-–}" "${sM:-–}" "${pM:-–}" \
        "$(ratio "$ps" "$ss")" "$(ratio "$sm" "$pm")" "$(ratio "$sM" "$pM")"
done
echo
echo "  size advantage  = protobuf_bytes / sofab_bytes   (>1: SofaBuffers smaller on the wire)"
echo "  MB/s advantage  = sofab_MBps  / protobuf_MBps    (bytes/s;    embeds the wire-size gap — see #85)"
echo "  msg/s advantage = sofab_msgs  / protobuf_msgs    (messages/s; size-neutral per-message codec speed)"
for lang in $maxspeed_langs; do
    c="${CODEC[$lang,sofab]:-}"; [ -n "$c" ] && echo "  sofab codec ($lang): $c"
done
fi

# ============================ embedded: two tables ============================
# Host-run embedded targets (they emit BENCH lines) get a throughput table with
# the IDENTICAL columns as MAXSPEED — kept separate because the impls are
# embedded-friendly (fixed capacity, -Os), so speed is informational here, not
# the ranking metric. Footprint is the bare-metal --gc-sections link delta
# (targets without BENCH data are the build-only cross targets); the host
# object-sum lines are still emitted/collected but no longer tabulated (raw
# data in results/raw/) — the link delta is the number that matters.
embedded_langs="$(langs_in embedded)"
emb_host=""; emb_metal=""
for lang in $embedded_langs; do
    if [ -n "${SER[$lang,sofab]:-}" ]; then emb_host="$emb_host$lang "; else emb_metal="$emb_metal$lang "; fi
done

# ---- embedded table 1: throughput (host builds of the embedded codecs) ------
if [ -n "$emb_host" ]; then
echo
echo "================================================================================"
echo " EMBEDDED — throughput (host build of the embedded codecs)"
echo "   same message/values/columns as MAXSPEED, but embedded-friendly impls (-Os,"
echo "   fixed capacity): speed is an interesting factor, NOT the ranking metric."
echo "   MB/s is within-row only — never compare rows."
echo "================================================================================"
printf "  %-37s | %14s | %20s | %20s | %23s\n" "opponent" "wire size (B)" "throughput MB/s" "throughput msgs/s" "sofab advantage"
printf "  %-37s | %6s %7s | %9s %10s | %9s %10s | %7s %7s %7s\n" "" "sofab" "proto" "sofab" "proto" "sofab" "proto" "size" "MB/s" "msg/s"
printf '  '; printf -- '-%.0s' $(seq 1 126); printf '\n'
for lang in $emb_host; do
    ss="${SER[$lang,sofab]:-}"; sm="$(mbps "$lang,sofab")"; sM="$(msgs_s "$lang,sofab")"
    for impl in $(ordered_impls "$lang"); do
        [ "$impl" = sofab ] && continue
        ps="${SER[$lang,$impl]:-}"; pm="$(mbps "$lang,$impl")"; pM="$(msgs_s "$lang,$impl")"
        [ -z "$ps$pm" ] && continue
        printf "  %-37s | %6s %7s | %9s %10s | %9s %10s | %6sx %6sx %6sx\n" \
            "sofab-$lang vs. $impl" \
            "${ss:-–}" "${ps:-–}" "${sm:-–}" "${pm:-–}" "${sM:-–}" "${pM:-–}" \
            "$(ratio "$ps" "$ss")" "$(ratio "$sm" "$pm")" "$(ratio "$sM" "$pM")"
    done
done
fi

# ---- embedded table 2: bare-metal link-delta footprint ------------------------
if [ -n "$emb_metal" ]; then
echo
echo "================================================================================"
echo " EMBEDDED — code footprint, bare-metal --gc-sections link delta"
echo "   codec program minus empty baseline, cross-compiled -Os -flto -DNDEBUG"
echo "   (Rust: no_std staticlib, opt-level=z, LTO) — the flash/RAM the codec"
echo "   actually adds to real firmware. Build-only, never executed. bytes; LOWER"
echo "   is better. RANKED BY footprint = .text + .rodata + .data: everything that"
echo "   ends up in flash (.data initializer images live in flash and are copied"
echo "   to RAM at boot). static-RAM = .data + .bss (.bss is RAM-only, no flash)."
echo "================================================================================"
printf "  %-14s %-13s | %8s %8s %7s %10s %11s\n" \
    "target" "impl" ".text" ".rodata" ".data" "footprint" "static-RAM"
printf '  '; printf -- '-%.0s' $(seq 1 74); printf '\n'
for lang in $emb_metal; do
    first=1
    for impl in $(ordered_impls "$lang"); do
        t="${TEXT[$lang,$impl]:-}"; [ -n "$t" ] || continue
        r="${RODATA[$lang,$impl]:-0}"; d="${DATA[$lang,$impl]:-0}"
        fp="$(awk -v t="$t" -v r="$r" -v d="$d" 'BEGIN{printf "%d", t+r+d}')"
        ram="$(awk -v d="$d" -v b="${BSS[$lang,$impl]:-0}" 'BEGIN{printf "%d", d+b}')"
        printf "  %-14s %-13s | %8s %8s %7s %10s %11s\n" \
            "$([ "$first" = 1 ] && echo "$lang" || echo "")" "$impl" "$t" "$r" "$d" "$fp" "$ram"
        first=0
    done
done
fi

# ------------------------------------------------------------------- status
echo
echo "  status per language:"
for lang in $LANGS; do printf "    %-14s %-9s %s\n" "$lang" "[${CATEGORY[$lang]:-?}]" "${STATUS[$lang]:-?}"; done
} | tee "$ROOT/results/RESULTS.txt"

echo
echo "wrote results/RESULTS.txt (raw BENCH/FOOTPRINT lines + logs under results/raw/)."
