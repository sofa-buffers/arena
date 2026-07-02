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
# (embedded targets emit both; maxspeed targets emit BENCH only.)
#
# Usage:
#   ./scripts/run_benchmark.sh                 # setup + run every language
#   ./scripts/run_benchmark.sh --no-setup      # skip setup.sh (reuse builds)
#   LANGS="python go" ./scripts/run_benchmark.sh
#   BENCH_ITERS=100000 ./scripts/run_benchmark.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LANGS="${LANGS:-c cpp rust go csharp java typescript python rust-embedded cpp-embedded}"
DO_SETUP=1
[ "${1:-}" = "--no-setup" ] && DO_SETUP=0

export STATE_JSON="$ROOT/schema/state.json"
export SOFABGEN="$ROOT/tools/sofabgen"

RAW="$ROOT/results/raw"; mkdir -p "$RAW"
export PATH="$HOME/.cargo/bin:/usr/local/cargo/bin:/usr/local/dotnet:$PATH"
export DOTNET_ROOT="${DOTNET_ROOT:-/usr/local/dotnet}"

declare -A SER MBS ITERS SHA CPU STATUS
declare -A TEXT RODATA DATA BSS         # footprint sections (embedded targets)
declare -A CATEGORY METRIC              # per-language, from languages/<lang>/meta
declare -A IMPLS                        # lang -> space-separated impls seen

REF_SOFAB_SHA="db362bf24959b41fd153b59958e2afdf59020c6c3501fb60e189526659a72ed4"
REF_PROTO_SHA="e8d391d98bc54c0ec24fff19ec96bb52114d9d34aed7d0f0023a0317bcfa5b3d"
# The C backend is the SofaBuffers *object API* (corelib-c-cpp), which drops the
# one empty string in string_array — a documented leanness optimization — so its
# wire is 434 B, not 436 B. This is the correct output of that backend, not drift.
REF_SOFAB_C_SHA="e1733416c987b04faea747b7cdd8f2913934f45d4a77453f58c9e3ef12e29d9d"
expected_sofab_sha() { [ "$1" = c ] && echo "$REF_SOFAB_C_SHA" || echo "$REF_SOFAB_SHA"; }
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
            ITERS[$key]="$(field "$line" iters)"
            CPU[$key]="$(field "$line" cpu_time_s)"
            MBS[$key]="$(field "$line" throughput_mbs)"
            SHA[$key]="$(field "$line" sha256)"
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
    echo "--- bench ($lang) ---"
    if ! "$dir/bench.sh" >"$RAW/$lang.out" 2>"$RAW/$lang.err"; then
        echo "!! bench FAILED for $lang (see $RAW/$lang.err)"; STATUS[$lang]=BENCH_FAIL
    else
        STATUS[$lang]=OK
    fi
    while IFS= read -r line; do
        case "$line" in BENCH*|FOOTPRINT*) parse_line "$line"; echo "  $line";; esac
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
        note=""; [ "$lang" = c ] && [ "$impl" = sofab ] && note="  (object API: drops empty string)"
        if [ "$s" = "$ref" ]; then mark="ok"; else mark="MISMATCH"; gate_ok=0; fi
        printf "  %-14s %-13s %s  %s%s\n" "$lang" "$impl" "${SER[$lang,$impl]:-?}B" "$mark" "$note"
    done
done
[ "$gate_ok" = 1 ] && echo "  => all present targets are byte-identical to the reference wire." \
                    || echo "  => WARNING: some targets diverge from the reference wire (fill drift)."

# ---------------------------------------------------------------- reporting helpers
mbps() { printf '%s' "${MBS[$1]:-}"; }
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
echo "   same message, same values. size in bytes; speed in MB/s (higher is better)."
echo "   MB/s is within-language only (different runtimes) — never compare rows."
echo "================================================================================"
printf "  %-11s | %14s | %20s | %20s\n" "language" "wire size (B)" "throughput MB/s" "sofab advantage"
printf "  %-11s | %6s %7s | %9s %10s | %8s %11s\n" "" "sofab" "proto" "sofab" "proto" "size" "speed"
printf '  '; printf -- '-%.0s' $(seq 1 76); printf '\n'
for lang in $maxspeed_langs; do
    ss="${SER[$lang,sofab]:-}"; ps="${SER[$lang,protobuf]:-}"
    sm="$(mbps "$lang,sofab")"; pm="$(mbps "$lang,protobuf")"
    [ -z "$ss$ps$sm$pm" ] && continue
    printf "  %-11s | %6s %7s | %9s %10s | %7sx %10sx\n" \
        "$lang" "${ss:-–}" "${ps:-–}" "${sm:-–}" "${pm:-–}" \
        "$(ratio "$ps" "$ss")" "$(ratio "$sm" "$pm")"
done
echo
echo "  size advantage  = protobuf_bytes / sofab_bytes   (>1: SofaBuffers smaller on the wire)"
echo "  speed advantage = sofab_MBps / protobuf_MBps     (>1: SofaBuffers encodes+decodes faster)"
fi

# ============================ embedded: footprint ============================
embedded_langs="$(langs_in embedded)"
if [ -n "$embedded_langs" ]; then
echo
echo "================================================================================"
echo " EMBEDDED — SofaBuffers vs footprint-oriented Protobuf, code+RAM footprint"
echo "   isolated codec built -Os (no harness/libc); bytes. LOWER is better."
echo "   static-RAM = .data + .bss.  '.text vs sofab' >1 means the baseline is fatter."
echo "================================================================================"
printf "  %-14s %-13s | %5s | %8s %8s %11s | %8s | %13s\n" \
    "target" "impl" "wire" ".text" ".rodata" "static-RAM" "MB/s" ".text vs sofab"
printf '  '; printf -- '-%.0s' $(seq 1 86); printf '\n'
for lang in $embedded_langs; do
    st="${TEXT[$lang,sofab]:-}"
    first=1
    for impl in $(ordered_impls "$lang"); do
        w="${SER[$lang,$impl]:-–}"; t="${TEXT[$lang,$impl]:-}"; m="$(mbps "$lang,$impl")"
        if [ -n "$t" ]; then
            r="${RODATA[$lang,$impl]:-–}"
            ram="$(awk -v d="${DATA[$lang,$impl]:-0}" -v b="${BSS[$lang,$impl]:-0}" 'BEGIN{printf "%d", d+b}')"
            if [ "$impl" = sofab ]; then tvs="1.00x"; elif [ -n "$st" ]; then tvs="$(ratio "$t" "$st")x"; else tvs="–"; fi
        else
            t="–"; r="–"; ram="–"; tvs="–"       # footprint pending (e.g. Rust: needs bare-metal ARM)
        fi
        printf "  %-14s %-13s | %5s | %8s %8s %11s | %8s | %13s\n" \
            "$([ "$first" = 1 ] && echo "$lang" || echo "")" "$impl" \
            "$w" "$t" "$r" "$ram" "${m:-–}" "$tvs"
        first=0
    done
done
echo
echo "  Footprint = object-sum of each library's OWN compiled code (no libc), built -Os."
echo "  It counts the whole library, so it over-counts generic runtimes that --gc-sections"
echo "  would trim on real hardware; a bare-metal --gc-sections build is the fair metric (TODO)."
echo "  MB/s = encode+decode throughput (secondary here)."
fi

# ------------------------------------------------------------------- status
echo
echo "  status per language:"
for lang in $LANGS; do printf "    %-14s %-9s %s\n" "$lang" "[${CATEGORY[$lang]:-?}]" "${STATUS[$lang]:-?}"; done
} | tee "$ROOT/results/RESULTS.txt"

echo
echo "wrote results/RESULTS.txt (raw BENCH/FOOTPRINT lines + logs under results/raw/)."
