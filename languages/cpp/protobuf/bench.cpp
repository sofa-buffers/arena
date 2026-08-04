// Protobuf C++ benchmark target.
//
// Encodes + decodes the canonical FullScaleExample message (schema/STATE.md)
// through protobuf's generated message.pb types. Same message, same state, same
// timed region as the SofaBuffers target. Prints one uniform BENCH line.
//
// ONE source, TWO builds, mirroring sofab/bench.cpp:
//
//   impl=protobuf         SerializeToString — one growable buffer per encode
//   impl=protobuf-stream  #108: BENCH_STREAM — SerializeToZeroCopyStream over a
//                         bounded block drained as it fills, protobuf's own answer
//                         to the same question. It is the opponent the runner
//                         pairs with impl=sofab-stream.
#ifndef _POSIX_C_SOURCE
#  define _POSIX_C_SOURCE 199309L
#endif

// Which impl this build measures; set by setup.sh (-DBENCH_IMPL).
#ifndef BENCH_IMPL
#  define BENCH_IMPL "protobuf"
#endif

#include <cfloat>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <string>

#ifdef BENCH_STREAM
#  include <cstring>
#  include <google/protobuf/io/zero_copy_stream.h>
#endif

#include "message.pb.h"
#include "sha256.h"

namespace {

#ifdef BENCH_STREAM
// The streaming counterpart of sofab's OStreamView-with-flush-callback: a
// ZeroCopyOutputStream that hands protobuf a bounded block and drains it into the
// sink each time protobuf asks for the next one. Same buffer size and same sink
// shape as sofab/bench.cpp, so the row differs in the codec and not in the
// harness around it.
#  ifndef STREAM_BUF_BYTES
#    define STREAM_BUF_BYTES 64
#  endif

std::uint8_t g_sink[2048];
std::size_t  g_sink_n = 0;

class DrainingStream final : public google::protobuf::io::ZeroCopyOutputStream
{
public:
    // protobuf takes back the bytes it did not use via BackUp(), so the amount
    // actually drained is `handed out - backed up` — tracked in pending_.
    bool Next(void **data, int *size) override
    {
        drain();
        *data = block_;
        *size = static_cast<int>(sizeof block_);
        pending_ = sizeof block_;
        return true;
    }
    void BackUp(int count) override { pending_ -= static_cast<std::size_t>(count); }
    google::protobuf::int64 ByteCount() const override
    {
        return static_cast<google::protobuf::int64>(total_ + pending_);
    }
    // Hand over whatever is still in the block; call once the encode is done.
    void finish() { drain(); }

private:
    void drain()
    {
        if (pending_ != 0) {
            std::memcpy(g_sink + g_sink_n, block_, pending_);
            g_sink_n += pending_;
            total_   += pending_;
            pending_  = 0;
        }
    }
    std::uint8_t block_[STREAM_BUF_BYTES];
    std::size_t  pending_ = 0;
    std::size_t  total_   = 0;
};

std::size_t stream_encode(const fullscale::FullScaleExample &m)
{
    g_sink_n = 0;
    DrainingStream out;
    m.SerializeToZeroCopyStream(&out);
    out.finish();
    return g_sink_n;
}
#endif

double now_seconds()
{
    struct timespec ts;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts);
    return static_cast<double>(ts.tv_sec) + static_cast<double>(ts.tv_nsec) / 1.0e9;
}

long bench_iters(long fallback)
{
    const char *s = getenv("BENCH_ITERS");
    if (s != nullptr && s[0] != '\0') {
        long v = atol(s);
        if (v > 0) {
            return v;
        }
    }
    return fallback;
}

} // namespace

int main()
{
    GOOGLE_PROTOBUF_VERIFY_VERSION;

    fullscale::FullScaleExample msg;

    msg.set_u8(200);
    msg.set_i8(-100);
    msg.set_u16(50000);
    msg.set_i16(-20000);
    msg.set_u32(3000000000U);
    msg.set_i32(-1000000000);
    msg.set_u64(10000000000000ULL);
    msg.set_i64(-5000000000000LL);

    fullscale::FullScaleSeqStruct* nested = msg.mutable_nested();
    nested->set_f32(3.14f);
    nested->set_f64(3.14159265);
    nested->set_str("Hello, World!");
    nested->set_bytes_field(std::string("\xDE\xAD\xBE\xEF", 4));

    fullscale::FullScaleSeqStructOfArrays* arrays = msg.mutable_arrays();
    for (uint32_t v : {0U, 64U, 128U, 191U, 255U}) arrays->add_u8(v);
    for (int32_t v : {-128, -64, 0, 63, 127}) arrays->add_i8(v);
    for (uint32_t v : {0U, 16384U, 32768U, 49151U, 65535U}) arrays->add_u16(v);
    for (int32_t v : {-32768, -16384, 0, 16383, 32767}) arrays->add_i16(v);
    for (uint32_t v : {0U, 1073741824U, 2147483648U, 3221225471U, 4294967295U}) arrays->add_u32(v);
    for (int32_t v : {INT32_MIN, -1073741824, 0, 1073741823, INT32_MAX}) arrays->add_i32(v);
    for (uint64_t v : {0ULL, 4611686018427387904ULL, 9223372036854775808ULL,
                       13835058055282163711ULL, 18446744073709551615ULL}) arrays->add_u64(v);
    for (int64_t v : {-9223372036854775807LL, -4611686018427387904LL, 0LL,
                      4611686018427387903LL, 9223372036854775807LL}) arrays->add_i64(v);

    fullscale::FullScaleSeqStructOfFpArrays* na = arrays->mutable_nested();
    for (float v : {1.0f, 2.0f, 3.0f, -FLT_MAX, FLT_MAX}) na->add_fp32(v);
    for (double v : {1.0, 2.0, 3.0, -DBL_MAX, DBL_MAX}) na->add_fp64(v);

    fullscale::FullScaleSeqArrayOfStrings* sa = msg.mutable_string_array();
    sa->add_strings("Hello, Sofab!");
    sa->add_strings("");
    sa->add_strings("1234567890");
    sa->add_strings("\xC3\xA4\xC3\xB6\xC3\xBC\xC3\x84\xC3\x96\xC3\x9C\xC3\x9F"); // "äöüÄÖÜß"
    sa->add_strings("This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}");

    // Warm-up round-trip + self-check (outside the timed region).
    std::string buffer;
    if (!msg.SerializeToString(&buffer)) {
        fprintf(stderr, "FAIL: protobuf serialize\n");
        return 1;
    }
    const size_t serialized = buffer.size();
    char sha[65];
    sha256_hex(buffer.data(), serialized, sha);

    fullscale::FullScaleExample check;
    if (!check.ParseFromString(buffer)) {
        fprintf(stderr, "FAIL: protobuf parse\n");
        return 1;
    }
#ifdef BENCH_STREAM
    if (stream_encode(check) != serialized ||
        std::memcmp(g_sink, buffer.data(), serialized) != 0) {
        fprintf(stderr, "FAIL: protobuf round-trip self-check\n");
        return 1;
    }
#else
    std::string reencoded;
    if (!check.SerializeToString(&reencoded) || reencoded != buffer) {
        fprintf(stderr, "FAIL: protobuf round-trip self-check\n");
        return 1;
    }
#endif

    // Timed loop: chained round trip — decode the reference wire, then re-encode
    // the freshly parsed message (issue #86). ParseFromString clears `dec` first,
    // so each iteration re-parses into a message whose cached serialized size is
    // reset — protobuf therefore pays the size pass every encode, as a real
    // proxy/transcode would, instead of hitting a once-per-instance memo.
    //
    // The DECODE half stays the plain one-shot parse in both builds — this row
    // varies the encode path only (#108).
    fullscale::FullScaleExample dec;
#ifndef BENCH_STREAM
    std::string out;
#endif
    const long iters = bench_iters(500000);
    const double t0 = now_seconds();
    for (long i = 0; i < iters; ++i) {
        dec.ParseFromString(buffer);
#ifdef BENCH_STREAM
        stream_encode(dec);
#else
        out.clear();
        dec.SerializeToString(&out);
#endif
    }
    const double t1 = now_seconds();

#ifdef BENCH_STREAM
    if (g_sink_n != serialized ||
        std::memcmp(g_sink, buffer.data(), serialized) != 0 ||
#else
    if (out != buffer ||
#endif
        dec.u8() != msg.u8() ||
        dec.string_array().strings_size() != 5 ||
        dec.arrays().i64_size() != 5) {
        fprintf(stderr, "FAIL: protobuf loop-path self-check\n");
        return 1;
    }

    const double cpu = t1 - t0;
    const double mbs = (cpu > 0.0)
        ? static_cast<double>(serialized) * static_cast<double>(iters) / cpu / 1.0e6
        : 0.0;
    printf("BENCH lang=cpp impl=%s serialized_bytes=%zu iters=%ld "
           "cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s\n",
           BENCH_IMPL, serialized, iters, cpu, mbs, sha);
    return 0;
}
