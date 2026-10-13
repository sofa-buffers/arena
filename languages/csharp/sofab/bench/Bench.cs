// SofaBuffers C# benchmark target.
// Encodes + decodes the canonical Example message, hand-filled from
// schema/STATE.md, through the sofabgen-generated Sofabuffers types. Same
// message, same state, same timed region as the Protobuf target.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using Sofabuffers;
using sofab;

static class Program {
    static double CpuSeconds() => Process.GetCurrentProcess().TotalProcessorTime.TotalSeconds;

    static Example Build() {
        var m = new Example {
            u8 = 200,
            i8 = -100,
            u16 = 50000,
            i16 = -20000,
            u32 = 3000000000,
            i32 = -1000000000,
            u64 = 10000000000000UL,
            i64 = -5000000000000L,
            nested = new Example_Nested {
                f32 = 3.14f,
                f64 = 3.14159265,
                str = "Hello, World!",
                bytes_field = new byte[] { 0xDE, 0xAD, 0xBE, 0xEF },
            },
            arrays = new Example_Arrays(),
            string_array = new List<string>(),
        };
        var a = m.arrays;
        a.u8 = new byte[] { 0, 64, 128, 191, 255 };
        a.i8 = new sbyte[] { -128, -64, 0, 63, 127 };
        a.u16 = new ushort[] { 0, 16384, 32768, 49151, 65535 };
        a.i16 = new short[] { -32768, -16384, 0, 16383, 32767 };
        a.u32 = new uint[] { 0, 1073741824, 2147483648, 3221225471, 4294967295 };
        a.i32 = new int[] { -2147483648, -1073741824, 0, 1073741823, 2147483647 };
        a.u64 = new ulong[] {
            0, 4611686018427387904, 9223372036854775808,
            13835058055282163711, 18446744073709551615 };
        a.i64 = new long[] {
            -9223372036854775807, -4611686018427387904, 0,
            4611686018427387903, 9223372036854775807 };
        a.nested = new Example_Arrays_Nested();
        a.nested.fp32 = new float[] { 1f, 2f, 3f, -float.MaxValue, float.MaxValue };
        a.nested.fp64 = new double[] { 1d, 2d, 3d, -double.MaxValue, double.MaxValue };
        m.string_array.AddRange(new string[] {
            "Hello, Sofab!", "", "1234567890", "äöüÄÖÜß",
            "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}" });
        return m;
    }

    static int Main() {
        // Caller-owned output buffer + encoder, hoisted out of the timed loop.
        var buf = new byte[Example.MaxSize];
        var os = new OStream(buf);

        // Warm-up round-trip + self-check (outside the timed region).
        Build().EncodeTo(os);
        byte[] blob = buf.AsSpan(0, os.BytesUsed).ToArray();
        int serialized = blob.Length;
        string sha = Convert.ToHexString(SHA256.HashData(blob)).ToLowerInvariant();
        os.Reset(buf, 0);
        Example.Decode(blob).EncodeTo(os);
        if (!buf.AsSpan(0, os.BytesUsed).SequenceEqual(blob)) {
            Console.Error.WriteLine("FAIL: sofab round-trip self-check");
            Environment.Exit(1);
        }

        long iters = long.Parse(Environment.GetEnvironmentVariable("BENCH_ITERS") ?? "2000000");

        // JIT warm-up (same chained shape as the timed loop).
        for (int i = 0; i < 5000; i++) {
            os.Reset(buf, 0);
            Example.Decode(blob).EncodeTo(os);
        }

        // Chained round trip: decode the reference wire, then re-encode the freshly
        // decoded message (issue #86). sink keeps the re-encode live.
        long sink = 0;
        double t0 = CpuSeconds();
        for (long i = 0; i < iters; i++) {
            os.Reset(buf, 0);
            Example.Decode(blob).EncodeTo(os);
            sink += os.BytesUsed;
        }
        double t1 = CpuSeconds();

        // Loop-path check: every re-encode had the reference length, and the last
        // one's bytes are the reference wire.
        if (sink != (long)serialized * iters || !buf.AsSpan(0, os.BytesUsed).SequenceEqual(blob)) {
            Console.Error.WriteLine("FAIL: sofab loop-path self-check");
            Environment.Exit(1);
        }

        double cpu = t1 - t0;
        double mbs = cpu > 0 ? (double)serialized * iters / cpu / 1e6 : 0.0;
        Console.WriteLine(
            $"BENCH lang=csharp impl=sofab serialized_bytes={serialized} iters={iters} " +
            $"cpu_time_s={cpu:F6} throughput_mbs={mbs:F2} sha256={sha}");
        return 0;
    }
}
