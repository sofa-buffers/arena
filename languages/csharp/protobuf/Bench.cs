// Protobuf C# benchmark target.
// Encodes + decodes the canonical FullScaleExample message, hand-filled from
// schema/STATE.md, through protobuf's generated Fullscale types. Same message,
// same state, same timed region as the SofaBuffers target.
//
// ONE source, TWO impls, selected by the BENCH_IMPL env var (#108):
//
//   protobuf         ToByteArray() -- one buffer the size of the whole message
//   protobuf-stream  WriteTo(CodedOutputStream) over a bounded buffer flushed
//                    into a Stream as it fills -- protobuf's own answer to the
//                    question sofab-stream asks. It is the opponent the runner
//                    pairs with impl=sofab-stream.
using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using Google.Protobuf;
using Fullscale;

static class Program {
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

    // Same sink shape as the sofab harness: the drained bytes land in a fixed
    // array, so the row compares codecs and not the harness around them.
    static readonly byte[] Sink = new byte[2048];
    static int sinkN;

    sealed class SinkStream : Stream {
        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => sinkN;
        public override long Position { get => sinkN; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override int Read(byte[] b, int o, int c) => throw new NotSupportedException();
        public override long Seek(long o, SeekOrigin r) => throw new NotSupportedException();
        public override void SetLength(long v) => throw new NotSupportedException();
        public override void Write(byte[] b, int o, int c) {
            Buffer.BlockCopy(b, o, Sink, sinkN, c);
            sinkN += c;
        }
    }

    static readonly SinkStream SinkOut = new SinkStream();

    /// <summary>Streaming encode through a <paramref name="cap"/>-byte buffer; returns bytes drained.</summary>
    static int StreamEncode(FullScaleExample m, int cap) {
        sinkN = 0;
        var cos = new CodedOutputStream(SinkOut, cap, leaveOpen: true);
        m.WriteTo(cos);
        cos.Flush();
        return sinkN;
    }

    static int Main() {
        var src = Build();
        var parser = FullScaleExample.Parser;

        string impl = Environment.GetEnvironmentVariable("BENCH_IMPL") ?? "protobuf";
        bool streaming = impl == "protobuf-stream";
        int streamCap = int.Parse(Environment.GetEnvironmentVariable("STREAM_BUF_BYTES") ?? "64");

        // Warm-up round-trip + self-check (outside the timed region).
        byte[] blob = src.ToByteArray();
        int serialized = blob.Length;
        string sha = Convert.ToHexString(SHA256.HashData(blob)).ToLowerInvariant();
        // The check runs through whichever encode path this impl measures.
        bool ok = streaming
            ? StreamEncode(parser.ParseFrom(blob), streamCap) == serialized
              && ((ReadOnlySpan<byte>)Sink).Slice(0, serialized).SequenceEqual(blob)
            : ((ReadOnlySpan<byte>)parser.ParseFrom(blob).ToByteArray()).SequenceEqual(blob);
        if (!ok) {
            Console.Error.WriteLine("FAIL: protobuf round-trip self-check");
            Environment.Exit(1);
        }

        long iters = long.Parse(Environment.GetEnvironmentVariable("BENCH_ITERS") ?? "2000000");

        // JIT warm-up (same chained shape as the timed loop).
        for (int i = 0; i < 5000; i++) {
            if (streaming) StreamEncode(parser.ParseFrom(blob), streamCap);
            else parser.ParseFrom(blob).ToByteArray();
        }

        // Chained round trip: decode the reference wire, then re-encode the freshly
        // parsed message (issue #86) — the proxy/transcode shape. Each ParseFrom
        // yields a new message whose cached serialized size is unset, so protobuf
        // pays the size pass every encode instead of hitting a once-per-instance
        // memo. sink keeps the re-encode live and doubles as a loop-path check.
        //
        // Two loops, picked before the stopwatch starts, so neither impl pays a
        // per-iteration branch the other does not.
        long sink = 0;
        Stopwatch sw;
        if (streaming) {
            sw = Stopwatch.StartNew();
            for (long i = 0; i < iters; i++) {
                sink += StreamEncode(parser.ParseFrom(blob), streamCap);
            }
        } else {
            sw = Stopwatch.StartNew();
            for (long i = 0; i < iters; i++) {
                sink += parser.ParseFrom(blob).ToByteArray().Length;
            }
        }
        sw.Stop();

        if (sink != (long)serialized * iters
            || (streaming && !((ReadOnlySpan<byte>)Sink).Slice(0, serialized).SequenceEqual(blob))) {
            Console.Error.WriteLine("FAIL: protobuf loop-path self-check");
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
