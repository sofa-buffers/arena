# shellcheck shell=bash
# Inter-impl cooldown — sourced by every bench.sh that times more than one impl.
#
# scripts/run_benchmark.sh idles COOLDOWN_S before each bench.sh so a target
# never starts on a hot CPU, but the impls INSIDE one bench.sh used to run
# back-to-back: the first one started cool and every later one ran on the heat
# its predecessors had just produced. Because the order within a row is fixed —
# and sofab goes first by convention — that bias was systematic, in the same
# direction, in every one of the RUNS repeats, so best-of-N could not average it
# out. Cooling between impls gives every impl of a row the same thermal starting
# point, which is the fairness rule the arena applies to everything else.
#
# COOLDOWN_S is exported by the runner. Run a bench.sh by hand and it is unset,
# which makes this a no-op — an interactive run stays as fast as it was.
#
# Logs to stderr: bench.sh stdout must carry nothing but BENCH/FOOTPRINT lines,
# since that output IS the runner's impl registry.
cooldown_between_impls() {
    local s="${COOLDOWN_S:-0}"
    case "$s" in '' | *[!0-9]*) return 0 ;; esac
    [ "$s" -gt 0 ] || return 0
    echo "    (cooling down ${s}s before the next impl)" >&2
    sleep "$s"
}
