#include "bench.h"   /* must be first: sets _POSIX_C_SOURCE for clock_gettime */

#include <string.h>
#include <float.h>
#include <pb_encode.h>
#include <pb_decode.h>
#include "message.pb.h"
#include "sha256.h"

static void fill(fullscale_FullScaleExample *m)
{
    memset(m, 0, sizeof(*m));

    /* Top-level scalars */
    m->u8  = 200;
    m->i8  = -100;
    m->u16 = 50000;
    m->i16 = -20000;
    m->u32 = 3000000000U;
    m->i32 = -1000000000;
    m->u64 = 10000000000000ULL;
    m->i64 = -5000000000000LL;

    /* Nested FullScaleSeqStruct (field id 10) */
    m->has_nested = true;
    m->nested.f32 = 3.14f;
    m->nested.f64 = 3.14159265;
    strcpy(m->nested.str, "Hello, World!");
    m->nested.bytes_field.size = 4;
    m->nested.bytes_field.bytes[0] = 0xDE;
    m->nested.bytes_field.bytes[1] = 0xAD;
    m->nested.bytes_field.bytes[2] = 0xBE;
    m->nested.bytes_field.bytes[3] = 0xEF;

    /* Arrays FullScaleSeqStructOfArrays (field id 100) */
    {
        const uint32_t u8_vals[5]  = {0, 64, 128, 191, 255};
        const int32_t  i8_vals[5]  = {-128, -64, 0, 63, 127};
        const uint32_t u16_vals[5] = {0, 16384, 32768, 49151, 65535};
        const int32_t  i16_vals[5] = {-32768, -16384, 0, 16383, 32767};
        const uint32_t u32_vals[5] = {0, 1073741824U, 2147483648U, 3221225471U, 4294967295U};
        const int32_t  i32_vals[5] = {-2147483648, -1073741824, 0, 1073741823, 2147483647};
        const uint64_t u64_vals[5] = {0ULL, 4611686018427387904ULL, 9223372036854775808ULL,
                                      13835058055282163711ULL, 18446744073709551615ULL};
        const int64_t  i64_vals[5] = {-9223372036854775807LL, -4611686018427387904LL, 0LL,
                                      4611686018427387903LL, 9223372036854775807LL};
        const float  fp32_vals[5]  = {1.0f, 2.0f, 3.0f, -FLT_MAX, FLT_MAX};
        const double fp64_vals[5]  = {1.0, 2.0, 3.0, -DBL_MAX, DBL_MAX};
        int i;

        m->has_arrays = true;
        m->arrays.u8_count = 5;  m->arrays.i8_count = 5;
        m->arrays.u16_count = 5; m->arrays.i16_count = 5;
        m->arrays.u32_count = 5; m->arrays.i32_count = 5;
        m->arrays.u64_count = 5; m->arrays.i64_count = 5;
        for (i = 0; i < 5; i++) {
            m->arrays.u8[i]  = u8_vals[i];
            m->arrays.i8[i]  = i8_vals[i];
            m->arrays.u16[i] = u16_vals[i];
            m->arrays.i16[i] = i16_vals[i];
            m->arrays.u32[i] = u32_vals[i];
            m->arrays.i32[i] = i32_vals[i];
            m->arrays.u64[i] = u64_vals[i];
            m->arrays.i64[i] = i64_vals[i];
        }
        m->arrays.has_nested = true;
        m->arrays.nested.fp32_count = 5;
        m->arrays.nested.fp64_count = 5;
        for (i = 0; i < 5; i++) {
            m->arrays.nested.fp32[i] = fp32_vals[i];
            m->arrays.nested.fp64[i] = fp64_vals[i];
        }
    }

    /* String array FullScaleSeqArrayOfStrings (field id 200) */
    m->has_string_array = true;
    m->string_array.strings_count = 5;
    strcpy(m->string_array.strings[0], "Hello, Sofab!");
    strcpy(m->string_array.strings[1], "");
    strcpy(m->string_array.strings[2], "1234567890");
    strcpy(m->string_array.strings[3], "\xc3\xa4\xc3\xb6\xc3\xbc\xc3\x84\xc3\x96\xc3\x9c\xc3\x9f");
    strcpy(m->string_array.strings[4], "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}");
}

int main(void)
{
    fullscale_FullScaleExample msg;
    fill(&msg);

    /* One round-trip up front: capture size + sha, self-check re-encode. */
    static uint8_t buffer[fullscale_FullScaleExample_size];
    pb_ostream_t os = pb_ostream_from_buffer(buffer, sizeof(buffer));
    if (!pb_encode(&os, fullscale_FullScaleExample_fields, &msg)) {
        fprintf(stderr, "FAIL: nanopb encode: %s\n", PB_GET_ERROR(&os));
        return 1;
    }
    size_t serialized = os.bytes_written;
    bench_dump("nanopb", buffer, serialized);

    char sha[65];
    sha256_hex(buffer, serialized, sha);

    /* self-check: decode, then re-encode and assert identical bytes */
    fullscale_FullScaleExample chk;
    memset(&chk, 0, sizeof(chk));
    pb_istream_t is = pb_istream_from_buffer(buffer, serialized);
    if (!pb_decode(&is, fullscale_FullScaleExample_fields, &chk)) {
        fprintf(stderr, "FAIL: nanopb decode: %s\n", PB_GET_ERROR(&is));
        return 1;
    }
    static uint8_t rebuf[fullscale_FullScaleExample_size];
    pb_ostream_t ros = pb_ostream_from_buffer(rebuf, sizeof(rebuf));
    if (!pb_encode(&ros, fullscale_FullScaleExample_fields, &chk) ||
        ros.bytes_written != serialized ||
        memcmp(rebuf, buffer, serialized) != 0) {
        fprintf(stderr, "FAIL: nanopb round-trip self-check\n");
        return 1;
    }

    /* Timed loop: ONLY encode + decode. */
    fullscale_FullScaleExample dec;
    const long iters = bench_iters(500000);
    long i;
    bench_instr_start();
    const double t0 = bench_seconds();
    for (i = 0; i < iters; i++) {
        pb_ostream_t o = pb_ostream_from_buffer(buffer, sizeof(buffer));
        pb_encode(&o, fullscale_FullScaleExample_fields, &msg);
        memset(&dec, 0, sizeof(dec));
        pb_istream_t in = pb_istream_from_buffer(buffer, o.bytes_written);
        pb_decode(&in, fullscale_FullScaleExample_fields, &dec);
    }
    const double t1 = bench_seconds();
    bench_instr_stop();

    const double cpu = t1 - t0;
    const double mbs = (cpu > 0.0) ? ((double)serialized * (double)iters) / cpu / 1.0e6 : 0.0;
    printf("BENCH lang=c-embedded impl=nanopb serialized_bytes=%zu iters=%ld cpu_time_s=%.6f "
           "throughput_mbs=%.2f sha256=%s\n", serialized, iters, cpu, mbs, sha);
    fflush(stdout);
    return 0;
}
