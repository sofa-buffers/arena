/* Shared timing/harness helpers for this target's embedded-C benches
 * (sofab/, protobuf/, nanopb/). Lives with the c-embedded target that owns it.
 *
 * Must be #included FIRST in every bench.c: it defines _POSIX_C_SOURCE before
 * <time.h> so clock_gettime(CLOCK_PROCESS_CPUTIME_ID) is visible under -std=c99,
 * and it pulls in the stdio/stdint/stddef declarations the bench sources rely on.
 *
 * All helpers are header-only (static inline); each bench.c is its own program,
 * so there is no multiple-definition concern.
 *
 * Provides:
 *   bench_seconds()      -> process CPU time in seconds (double)
 *   bench_iters(dflt)    -> iteration count, overridable via $BENCH_ITERS
 */
#ifndef SOFAB_ARENA_C_EMBEDDED_BENCH_H
#define SOFAB_ARENA_C_EMBEDDED_BENCH_H

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 199309L   /* clock_gettime + CLOCK_PROCESS_CPUTIME_ID */
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* Process CPU seconds (docs/BENCH.md: CPU time, not wall clock); 0 if the clock
 * is unavailable, so a failed read yields throughput 0 rather than a bogus one. */
static inline double bench_seconds(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) != 0)
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

#endif /* SOFAB_ARENA_C_EMBEDDED_BENCH_H */
