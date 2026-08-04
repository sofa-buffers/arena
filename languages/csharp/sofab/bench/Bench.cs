// SofaBuffers C# benchmark target.
// Encodes + decodes the canonical Example message, hand-filled from
// schema/STATE.md, through the sofabgen-generated Sofabuffers types. Same
// message, same state, same timed region as the Protobuf target.
//
// ONE source, TWO impls, selected by the BENCH_IMPL env var (#108):
//
//   sofab         Encode() — one buffer the size of the whole message
//   sofab-stream  EncodeTo(OStream) over a buffer SMALLER than the message with
//                 a FlushSink draining it as it fills, so the encode's memory
//                 need is the buffer and not the message
//
// The two paths are separate loops chosen before timing starts, never a branch
// inside the timed region. Only the ENCODE half differs; the decode stays the
// plain one-shot Decode in both, so a row reflects one axis.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using sofab;          // OStream / FlushSink (corelib-cs)
using Sofabuffers;

static class Program {
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
            nested = new ExampleNested {
                f32 = 3.14f,
                f64 = 3.14159265,
                str = "Hello, World!",
                bytes_field = new byte[] { 0xDE, 0xAD, 0xBE, 0xEF },
            },
            arrays = new ExampleArrays(),
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
        a.nested = new ExampleArraysNested();
        a.nested.fp32 = new float[] { 1f, 2f, 3f, -float.MaxValue, float.MaxValue };
        a.nested.fp64 = new double[] { 1d, 2d, 3d, -double.MaxValue, double.MaxValue };
        m.string_array.AddRange(new string[] {
            "Hello, Sofab!", "", "1234567890", "äöüÄÖÜß",
            "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}" });
        return m;
    }

    // The drained bytes land here so the loop keeps a live sink and the result
    // stays checkable against the reference wire. The encoder never sees this
    // array -- only the FlushSink does.
    static readonly byte[] Sink = new byte[2048];
    static int sinkN;

    /// <summary>Streaming encode of <paramref name="m"/>; returns bytes drained.</summary>
    static int StreamEncode(Example m, OStream os) {
        sinkN = 0;
        m.EncodeTo(os);   // Serialize(os) + os.Flush(), which also rewinds os
        return sinkN;
    }

    static int Main() {
        var src = Build();

        string impl = Environment.GetEnvironmentVariable("BENCH_IMPL") ?? "sofab";
        bool streaming = impl == "sofab-stream";
        int streamCap = int.Parse(Environment.GetEnvironmentVariable("STREAM_BUF_BYTES") ?? "64");
        OStream? os = streaming
            ? new OStream(new byte[streamCap], 0, (data, off, len) => {
                  Buffer.BlockCopy(data, off, Sink, sinkN, len);
                  sinkN += len;
              })
            : null;

        // Warm-up round-trip + self-check (outside the timed region).
        byte[] blob = src.Encode();
        int serialized = blob.Length;
        string sha = Convert.ToHexString(SHA256.HashData(blob)).ToLowerInvariant();
        // The check runs through whichever encode path this impl measures, so a
        // dropped or duplicated drained chunk fails here instead of being reported.
        bool ok = streaming
            ? StreamEncode(Example.Decode(blob), os!) == serialized
              && ((ReadOnlySpan<byte>)Sink).Slice(0, serialized).SequenceEqual(blob)
            : ((ReadOnlySpan<byte>)Example.Decode(blob).Encode()).SequenceEqual(blob);
        if (!ok) {
            Console.Error.WriteLine("FAIL: sofab round-trip self-check");
            Environment.Exit(1);
        }

        long iters = long.Parse(Environment.GetEnvironmentVariable("BENCH_ITERS") ?? "2000000");

        // JIT warm-up (same chained shape as the timed loop).
        for (int i = 0; i < 5000; i++) {
            if (streaming) StreamEncode(Example.Decode(blob), os!);
            else Example.Decode(blob).Encode();
        }

        // Chained round trip: decode the reference wire, then re-encode the freshly
        // decoded message (issue #86) — the proxy/transcode shape, which denies
        // protobuf its once-per-instance serialized-size memo so encode is measured
        // on equal terms. sink keeps the re-encode live and doubles as a loop-path
        // check (every re-encode is `serialized` bytes).
        //
        // Two loops, picked before the stopwatch starts: the impl must not cost a
        // branch per iteration that the other impl does not also pay.
        long sink = 0;
        Stopwatch sw;
        if (streaming) {
            sw = Stopwatch.StartNew();
            for (long i = 0; i < iters; i++) {
                sink += StreamEncode(Example.Decode(blob), os!);
            }
            sw.Stop();
        } else {
            sw = Stopwatch.StartNew();
            for (long i = 0; i < iters; i++) {
                sink += Example.Decode(blob).Encode().Length;
            }
            sw.Stop();
        }

        if (sink != (long)serialized * iters
            || (streaming && !((ReadOnlySpan<byte>)Sink).Slice(0, serialized).SequenceEqual(blob))) {
            Console.Error.WriteLine("FAIL: sofab loop-path self-check");
            Environment.Exit(1);
        }

        double cpu = sw.Elapsed.TotalSeconds;
        double mbs = cpu > 0 ? (double)serialized * iters / cpu / 1e6 : 0.0;
        Console.WriteLine(
            $"BENCH lang=csharp impl={impl} serialized_bytes={serialized} iters={iters} " +
            $"cpu_time_s={cpu:F6} throughput_mbs={mbs:F2} sha256={sha}");
        return 0;
    }
}
