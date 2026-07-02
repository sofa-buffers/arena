#include "bench.h"   /* must be first: sets _POSIX_C_SOURCE for clock_gettime */

#include <string.h>
#include <float.h>
#include "message.pb-c.h"
#include "sha256.h"

int main(void)
{
    /* Build the canonical FullScaleExample (schema/STATE.md). */
    Fullscale__FullScaleSeqStruct nested = FULLSCALE__FULL_SCALE_SEQ_STRUCT__INIT;
    nested.f32 = 3.14f;
    nested.f64 = 3.14159265;
    nested.str = (char *)"Hello, World!";
    static uint8_t bytes_field[4] = {0xDE, 0xAD, 0xBE, 0xEF};
    nested.bytes_field.len = 4;
    nested.bytes_field.data = bytes_field;

    static uint32_t u8_vals[5]  = {0, 64, 128, 191, 255};
    static int32_t  i8_vals[5]  = {-128, -64, 0, 63, 127};
    static uint32_t u16_vals[5] = {0, 16384, 32768, 49151, 65535};
    static int32_t  i16_vals[5] = {-32768, -16384, 0, 16383, 32767};
    static uint32_t u32_vals[5] = {0, 1073741824U, 2147483648U, 3221225471U, 4294967295U};
    static int32_t  i32_vals[5] = {-2147483648, -1073741824, 0, 1073741823, 2147483647};
    static uint64_t u64_vals[5] = {0ULL, 4611686018427387904ULL, 9223372036854775808ULL,
                                   13835058055282163711ULL, 18446744073709551615ULL};
    static int64_t  i64_vals[5] = {-9223372036854775807LL, -4611686018427387904LL, 0LL,
                                   4611686018427387903LL, 9223372036854775807LL};
    static float  fp32_vals[5]  = {1.0f, 2.0f, 3.0f, -FLT_MAX, FLT_MAX};
    static double fp64_vals[5]  = {1.0, 2.0, 3.0, -DBL_MAX, DBL_MAX};

    Fullscale__FullScaleSeqStructOfFpArrays fp = FULLSCALE__FULL_SCALE_SEQ_STRUCT_OF_FP_ARRAYS__INIT;
    fp.n_fp32 = 5; fp.fp32 = fp32_vals;
    fp.n_fp64 = 5; fp.fp64 = fp64_vals;

    Fullscale__FullScaleSeqStructOfArrays arrays = FULLSCALE__FULL_SCALE_SEQ_STRUCT_OF_ARRAYS__INIT;
    arrays.n_u8 = 5;  arrays.u8  = u8_vals;
    arrays.n_i8 = 5;  arrays.i8  = i8_vals;
    arrays.n_u16 = 5; arrays.u16 = u16_vals;
    arrays.n_i16 = 5; arrays.i16 = i16_vals;
    arrays.n_u32 = 5; arrays.u32 = u32_vals;
    arrays.n_i32 = 5; arrays.i32 = i32_vals;
    arrays.n_u64 = 5; arrays.u64 = u64_vals;
    arrays.n_i64 = 5; arrays.i64 = i64_vals;
    arrays.nested = &fp;

    static char *strings[5] = {
        (char *)"Hello, Sofab!",
        (char *)"",
        (char *)"1234567890",
        (char *)"\xc3\xa4\xc3\xb6\xc3\xbc\xc3\x84\xc3\x96\xc3\x9c\xc3\x9f",
        (char *)"This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}"
    };
    Fullscale__FullScaleSeqArrayOfStrings string_array = FULLSCALE__FULL_SCALE_SEQ_ARRAY_OF_STRINGS__INIT;
    string_array.n_strings = 5;
    string_array.strings = strings;

    Fullscale__FullScaleExample msg = FULLSCALE__FULL_SCALE_EXAMPLE__INIT;
    msg.u8  = 200;
    msg.i8  = -100;
    msg.u16 = 50000;
    msg.i16 = -20000;
    msg.u32 = 3000000000U;
    msg.i32 = -1000000000;
    msg.u64 = 10000000000000ULL;
    msg.i64 = -5000000000000LL;
    msg.nested = &nested;
    msg.arrays = &arrays;
    msg.string_array = &string_array;

    /* One round-trip up front: capture size + sha, self-check re-encode. */
    size_t serialized = fullscale__full_scale_example__get_packed_size(&msg);
    uint8_t *buffer = (uint8_t *)malloc(serialized);
    if (buffer == NULL) { fprintf(stderr, "FAIL: oom\n"); return 1; }
    size_t packed = fullscale__full_scale_example__pack(&msg, buffer);
    if (packed != serialized) { fprintf(stderr, "FAIL: protobuf pack size\n"); return 1; }
    bench_dump("protobuf-c", buffer, serialized);

    char sha[65];
    sha256_hex(buffer, serialized, sha);

    Fullscale__FullScaleExample *chk =
        fullscale__full_scale_example__unpack(NULL, serialized, buffer);
    if (chk == NULL) { fprintf(stderr, "FAIL: protobuf unpack\n"); return 1; }
    uint8_t *rebuf = (uint8_t *)malloc(serialized);
    size_t re = fullscale__full_scale_example__pack(chk, rebuf);
    if (re != serialized || memcmp(rebuf, buffer, serialized) != 0) {
        fprintf(stderr, "FAIL: protobuf round-trip self-check\n");
        return 1;
    }
    free(rebuf);
    fullscale__full_scale_example__free_unpacked(chk, NULL);

    /* Timed loop: ONLY encode (pack) + decode (unpack). Buffer hoisted out. */
    const long iters = bench_iters(500000);
    long i;
    bench_instr_start();
    const double t0 = bench_seconds();
    for (i = 0; i < iters; i++) {
        fullscale__full_scale_example__pack(&msg, buffer);
        Fullscale__FullScaleExample *d =
            fullscale__full_scale_example__unpack(NULL, serialized, buffer);
        fullscale__full_scale_example__free_unpacked(d, NULL);
    }
    const double t1 = bench_seconds();
    bench_instr_stop();

    const double cpu = t1 - t0;
    const double mbs = (cpu > 0.0) ? ((double)serialized * (double)iters) / cpu / 1.0e6 : 0.0;
    printf("BENCH lang=c-embedded impl=protobuf-c serialized_bytes=%zu iters=%ld cpu_time_s=%.6f "
           "throughput_mbs=%.2f sha256=%s\n", serialized, iters, cpu, mbs, sha);
    fflush(stdout);

    free(buffer);
    return 0;
}
