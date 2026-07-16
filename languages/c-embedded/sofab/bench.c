#include "bench.h"   /* must be first: sets _POSIX_C_SOURCE for clock_gettime */

#include <float.h>
#include <string.h>
#include "example.h"   /* generated from schema/message.sofab.yaml by sofabgen (--lang c) */
#include "sha256.h"

static void fill(fullscale_example_t *m)
{
    memset(m, 0, sizeof(*m));

    /* Fill scalar fields */
    m->u8  = 200;
    m->i8  = -100;
    m->u16 = 50000;
    m->i16 = -20000;
    m->u32 = 3000000000U;
    m->i32 = -1000000000;
    m->u64 = 10000000000000ULL;
    m->i64 = -5000000000000LL;

    /* Fill nested FullScaleSeqStruct (field id 10) */
    m->nested.f32 = 3.14f;
    m->nested.f64 = 3.14159265;
    strncpy(m->nested.str, "Hello, World!", sizeof(m->nested.str));
    m->nested.bytes_field[0] = 0xDE;
    m->nested.bytes_field[1] = 0xAD;
    m->nested.bytes_field[2] = 0xBE;
    m->nested.bytes_field[3] = 0xEF;
    m->nested.bytes_field_len = 4;  /* sofabgen >= v0.17.1 sized-blob API: encode the true length */

    /* Fill arrays FullScaleSeqStructOfArrays (field id 100) */
    {
        const uint8_t  u8_vals[5]  = {0, 64, 128, 191, 255};
        const int8_t   i8_vals[5]  = {-128, -64, 0, 63, 127};
        const uint16_t u16_vals[5] = {0, 16384, 32768, 49151, 65535};
        const int16_t  i16_vals[5] = {-32768, -16384, 0, 16383, 32767};
        const uint32_t u32_vals[5] = {0, 1073741824U, 2147483648U, 3221225471U, 4294967295U};
        const int32_t  i32_vals[5] = {-2147483648, -1073741824, 0, 1073741823, 2147483647};
        const uint64_t u64_vals[5] = {0ULL, 4611686018427387904ULL, 9223372036854775808ULL,
                                      13835058055282163711ULL, 18446744073709551615ULL};
        const int64_t  i64_vals[5] = {-9223372036854775807LL, -4611686018427387904LL, 0LL,
                                      4611686018427387903LL, 9223372036854775807LL};
        const float  fp32_vals[5]  = {1.0f, 2.0f, 3.0f, -FLT_MAX, FLT_MAX};
        const double fp64_vals[5]  = {1.0, 2.0, 3.0, -DBL_MAX, DBL_MAX};
        size_t i;
        for (i = 0; i < 5; i++) {
            m->arrays.u8[i]  = u8_vals[i];
            m->arrays.i8[i]  = i8_vals[i];
            m->arrays.u16[i] = u16_vals[i];
            m->arrays.i16[i] = i16_vals[i];
            m->arrays.u32[i] = u32_vals[i];
            m->arrays.i32[i] = i32_vals[i];
            m->arrays.u64[i] = u64_vals[i];
            m->arrays.i64[i] = i64_vals[i];
            m->arrays.nested.fp32[i] = fp32_vals[i];
            m->arrays.nested.fp64[i] = fp64_vals[i];
        }
    }

    /* Fill string array (field id 200) */
    strncpy(m->string_array.items[0], "Hello, Sofab!", sizeof(m->string_array.items[0]));
    strncpy(m->string_array.items[1], "", sizeof(m->string_array.items[1]));
    strncpy(m->string_array.items[2], "1234567890", sizeof(m->string_array.items[2]));
    strncpy(m->string_array.items[3], "\xc3\xa4\xc3\xb6\xc3\xbc\xc3\x84\xc3\x96\xc3\x9c\xc3\x9f",
            sizeof(m->string_array.items[3]));
    strncpy(m->string_array.items[4], "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}",
            sizeof(m->string_array.items[4]));
}

int main(void)
{
    fullscale_example_t msg;
    fill(&msg);

    /* One round-trip up front: capture the serialized size + sha, verify correctness. */
    uint8_t buffer[FULLSCALE_EXAMPLE_MAX_SIZE];
    size_t serialized = 0;
    if (fullscale_example_encode(&msg, buffer, sizeof(buffer), &serialized) != SOFAB_RET_OK) {
        fprintf(stderr, "FAIL: sofab encode\n");
        return 1;
    }
    bench_dump("sofab-c", buffer, serialized);

    char sha[65];
    sha256_hex(buffer, serialized, sha);

    /* self-check: decode, then re-encode and assert identical bytes */
    fullscale_example_t check;
    memset(&check, 0, sizeof(check));
    if (fullscale_example_decode(&check, buffer, serialized) != SOFAB_RET_OK) {
        fprintf(stderr, "FAIL: sofab decode\n");
        return 1;
    }
    uint8_t rebuf[FULLSCALE_EXAMPLE_MAX_SIZE];
    size_t reused = 0;
    if (fullscale_example_encode(&check, rebuf, sizeof(rebuf), &reused) != SOFAB_RET_OK ||
        reused != serialized || memcmp(rebuf, buffer, serialized) != 0) {
        fprintf(stderr, "FAIL: sofab round-trip self-check\n");
        return 1;
    }

    /* Timed loop: ONLY encode + decode. */
    fullscale_example_t dec;
    memset(&dec, 0, sizeof(dec));
    const long iters = bench_iters(500000);
    long i;
    bench_instr_start();
    const double t0 = bench_seconds();
    for (i = 0; i < iters; i++) {
        size_t used;
        fullscale_example_encode(&msg, buffer, sizeof(buffer), &used);
        fullscale_example_decode(&dec, buffer, used);
    }
    const double t1 = bench_seconds();
    bench_instr_stop();

    const double cpu = t1 - t0;
    const double mbs = (cpu > 0.0) ? ((double)serialized * (double)iters) / cpu / 1.0e6 : 0.0;
    printf("BENCH lang=c-embedded impl=sofab serialized_bytes=%zu iters=%ld cpu_time_s=%.6f "
           "throughput_mbs=%.2f sha256=%s\n", serialized, iters, cpu, mbs, sha);
    fflush(stdout);
    return 0;
}
