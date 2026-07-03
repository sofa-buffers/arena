/* Shared timing/harness helpers for this target's embedded-C benches
 * (sofab/, protobuf/, nanopb/). Lives with the c-embedded target that owns it.
 *
 * Must be #included FIRST in every bench.c: it defines _POSIX_C_SOURCE before
 * <time.h> so clock_gettime(CLOCK_MONOTONIC) is visible under -std=c99, and it
 * pulls in the stdio/stdint/stddef declarations the bench sources rely on.
 *
 * All helpers are header-only (static inline); each bench.c is its own program,
 * so there is no multiple-definition concern.
 *
 * Provides:
 *   bench_seconds()      -> monotonic wall-clock seconds (double)
 *   bench_iters(dflt)    -> iteration count, overridable via $BENCH_ITERS
 *   bench_dump(tag,b,n)  -> hex dump of wire bytes to stderr when $BENCH_DUMP set
 *   bench_instr_start()  -> instrumentation hooks (no-ops; kept for call-site
 *   bench_instr_stop()      symmetry and future perf-counter wiring)
 */
#ifndef SOFAB_ARENA_C_EMBEDDED_BENCH_H
#define SOFAB_ARENA_C_EMBEDDED_BENCH_H

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 199309L   /* clock_gettime + CLOCK_MONOTONIC */
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* Monotonic seconds; falls back to 0 if the clock is unavailable so a failed
 * read yields throughput 0 rather than a bogus negative/huge number. */
static inline double bench_seconds(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0.0;
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1.0e-9;
}

/* Iteration count: honour $BENCH_ITERS (positive integer) if present, else the
 * caller's default. Keeps the C targets tunable the same way the others are. */
static inline long bench_iters(long dflt)
{
    const char *env = getenv("BENCH_ITERS");
    if (env != NULL && *env != '\0') {
        char *end = NULL;
        long v = strtol(env, &end, 10);
        if (end != env && v > 0)
            return v;
    }
    return dflt;
}

/* Diagnostic wire-bytes dump to stderr, off by default so stdout stays clean
 * for the single BENCH line the runner parses. Enable with BENCH_DUMP=1. */
static inline void bench_dump(const char *tag, const uint8_t *buf, size_t n)
{
    const char *env = getenv("BENCH_DUMP");
    if (env == NULL || *env == '\0' || *env == '0')
        return;
    fprintf(stderr, "DUMP %s bytes=%zu:", tag, n);
    for (size_t i = 0; i < n; i++)
        fprintf(stderr, " %02x", buf[i]);
    fputc('\n', stderr);
}

/* Instrumentation markers around the timed region. No-ops in the portable
 * build; present so bench sources can bracket the loop uniformly. */
static inline void bench_instr_start(void) { }
static inline void bench_instr_stop(void)  { }

#endif /* SOFAB_ARENA_C_EMBEDDED_BENCH_H */
