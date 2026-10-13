// Protobuf C# benchmark target.
// Encodes + decodes the canonical FullScaleExample message, hand-filled from
// schema/STATE.md, through protobuf's generated Fullscale types. Same message,
// same state, same timed region as the SofaBuffers target.
using System;
using System.Diagnostics;
using System.Security.Cryptography;
using Google.Protobuf;
using Fullscale;

static class Program {
    static double CpuSeconds() => Process.GetCurrentProcess().TotalProcessorTime.TotalSeconds;

    static FullScaleExample Build() {
        var m = new FullScaleExample {
            U8 = 200,
            I8 = -100,
            U16 = 50000,
            I16 = -20000,
            U32 = 3000000000,
            I32 = -1000000000,
            U64 = 10000000000000UL,
            I64 = -5000000000000L,
            Nested = new FullScaleSeqStruct {
                F32 = 3.14f,
                F64 = 3.14159265,
                Str = "Hello, World!",
                BytesField = ByteString.CopyFrom(new byte[] { 0xDE, 0xAD, 0xBE, 0xEF }),
            },
            Arrays = new FullScaleSeqStructOfArrays(),
            StringArray = new FullScaleSeqArrayOfStrings(),
        };
        var a = m.Arrays;
        a.U8.AddRange(new uint[] { 0, 64, 128, 191, 255 });
        a.I8.AddRange(new int[] { -128, -64, 0, 63, 127 });
        a.U16.AddRange(new uint[] { 0, 16384, 32768, 49151, 65535 });
        a.I16.AddRange(new int[] { -32768, -16384, 0, 16383, 32767 });
        a.U32.AddRange(new uint[] { 0, 1073741824, 2147483648, 3221225471, 4294967295 });
        a.I32.AddRange(new int[] { -2147483648, -1073741824, 0, 1073741823, 2147483647 });
        a.U64.AddRange(new ulong[] {
            0, 4611686018427387904, 9223372036854775808,
            13835058055282163711, 18446744073709551615 });
        a.I64.AddRange(new long[] {
            -9223372036854775807, -4611686018427387904, 0,
            4611686018427387903, 9223372036854775807 });
        a.Nested = new FullScaleSeqStructOfFpArrays();
        a.Nested.Fp32.AddRange(new float[] { 1f, 2f, 3f, -float.MaxValue, float.MaxValue });
        a.Nested.Fp64.AddRange(new double[] { 1d, 2d, 3d, -double.MaxValue, double.MaxValue });
        m.StringArray.Strings.AddRange(new string[] {
            "Hello, Sofab!", "", "1234567890", "äöüÄÖÜß",
            "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}" });
        return m;
    }

    static int Main() {
        var src = Build();
        var parser = FullScaleExample.Parser;

        // Caller-owned output buffer, hoisted out of the timed loop. protobuf has
        // no max-size constant, so it is sized from the reference message;
        // WriteTo(Span) takes a span of exactly CalculateSize() bytes.
        var buf = new byte[src.CalculateSize()];

        // Warm-up round-trip + self-check (outside the timed region).
        src.WriteTo(buf.AsSpan(0, src.CalculateSize()));
        byte[] blob = (byte[])buf.Clone();
        int serialized = blob.Length;
        string sha = Convert.ToHexString(SHA256.HashData(blob)).ToLowerInvariant();
        var msg = parser.ParseFrom(blob);
        int n = msg.CalculateSize();
        msg.WriteTo(buf.AsSpan(0, n));
        if (!buf.AsSpan(0, n).SequenceEqual(blob)) {
            Console.Error.WriteLine("FAIL: protobuf round-trip self-check");
            Environment.Exit(1);
        }

        long iters = long.Parse(Environment.GetEnvironmentVariable("BENCH_ITERS") ?? "2000000");

        // JIT warm-up (same chained shape as the timed loop).
        for (int i = 0; i < 5000; i++) {
            msg = parser.ParseFrom(blob);
            msg.WriteTo(buf.AsSpan(0, msg.CalculateSize()));
        }

        // Chained round trip: decode the reference wire, then re-encode the freshly
        // parsed message (issue #86). sink keeps the re-encode live.
        long sink = 0;
        double t0 = CpuSeconds();
        for (long i = 0; i < iters; i++) {
            msg = parser.ParseFrom(blob);
            n = msg.CalculateSize();
            msg.WriteTo(buf.AsSpan(0, n));
            sink += n;
        }
        double t1 = CpuSeconds();

        // Loop-path check: every re-encode had the reference length, and the last
        // one's bytes are the reference wire.
        if (sink != (long)serialized * iters || !buf.AsSpan(0, n).SequenceEqual(blob)) {
            Console.Error.WriteLine("FAIL: protobuf loop-path self-check");
            Environment.Exit(1);
        }

        double cpu = t1 - t0;
        double mbs = cpu > 0 ? (double)serialized * iters / cpu / 1e6 : 0.0;
        Console.WriteLine(
            $"BENCH lang=csharp impl=protobuf serialized_bytes={serialized} iters={iters} " +
            $"cpu_time_s={cpu:F6} throughput_mbs={mbs:F2} sha256={sha}");
        return 0;
    }
}
