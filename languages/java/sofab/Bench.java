// SofaBuffers Java benchmark target.
// Encodes + decodes the canonical FullScaleExample message (hand-filled from
// schema/STATE.md) through the generated message.Example type, backed by the
// real corelib-java runtime. Prints one uniform BENCH line (see docs/BENCH.md).
package bench;

import message.Example;

import org.sofabuffers.sofab.OStream;
import java.lang.management.ManagementFactory;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.List;

public class Bench {
    static String sha256hex(byte[] b) throws Exception {
        byte[] d = MessageDigest.getInstance("SHA-256").digest(b);
        StringBuilder sb = new StringBuilder(d.length * 2);
        for (byte x : d) sb.append(String.format("%02x", x & 0xFF));
        return sb.toString();
    }

    static long cpuNanos() {
        return ((com.sun.management.OperatingSystemMXBean)
            ManagementFactory.getOperatingSystemMXBean()).getProcessCpuTime();
    }

    static Example build() {
        Example m = new Example();
        m.u8 = 200;
        m.i8 = -100;
        m.u16 = 50000;
        m.i16 = -20000;
        m.u32 = 3000000000L;
        m.i32 = -1000000000;
        m.u64 = 10000000000000L;
        m.i64 = -5000000000000L;

        m.nested.f32 = 3.14f;
        m.nested.f64 = 3.14159265;
        m.nested.str = "Hello, World!";
        m.nested.bytes_field =
            new byte[]{(byte) 0xDE, (byte) 0xAD, (byte) 0xBE, (byte) 0xEF};

        m.arrays.u8 = new byte[]{0, 64, (byte) 128, (byte) 191, (byte) 255};
        m.arrays.i8 = new byte[]{-128, -64, 0, 63, 127};
        m.arrays.u16 = new short[]{0, 16384, (short) 32768, (short) 49151, (short) 65535};
        m.arrays.i16 = new short[]{-32768, -16384, 0, 16383, 32767};
        m.arrays.u32 = new int[]{0, 1073741824,
            (int) 2147483648L, (int) 3221225471L, (int) 4294967295L};
        m.arrays.i32 = new int[]{-2147483648, -1073741824, 0, 1073741823, 2147483647};
        m.arrays.u64 = new long[]{0L, 4611686018427387904L,
            Long.parseUnsignedLong("9223372036854775808"),
            Long.parseUnsignedLong("13835058055282163711"),
            Long.parseUnsignedLong("18446744073709551615")};
        m.arrays.i64 = new long[]{-9223372036854775807L, -4611686018427387904L, 0L,
            4611686018427387903L, 9223372036854775807L};
        m.arrays.nested.fp32 = new float[]{1f, 2f, 3f, -Float.MAX_VALUE, Float.MAX_VALUE};
        m.arrays.nested.fp64 = new double[]{1d, 2d, 3d, -Double.MAX_VALUE, Double.MAX_VALUE};

        m.string_array.addAll(List.of(
            "Hello, Sofab!",
            "",
            "1234567890",
            "äöüÄÖÜß",
            "This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}"));
        return m;
    }

    public static void main(String[] args) throws Exception {
        // Caller-owned output buffer + encoder, hoisted out of the timed loop.
        byte[] out = new byte[Example.MAX_SIZE];
        OStream os = new OStream(out);

        // Warm-up round-trip + self-check (outside the timed region).
        build().encodeTo(os);
        byte[] blob = Arrays.copyOf(out, os.bytesUsed());
        int serialized = blob.length;
        String sha = sha256hex(blob);
        os.reset(out);
        Example.decode(blob).encodeTo(os);
        if (!Arrays.equals(out, 0, os.bytesUsed(), blob, 0, serialized)) {
            System.err.println("FAIL: sofab round-trip self-check");
            System.exit(1);
        }

        int iters = Integer.parseInt(
            System.getenv().getOrDefault("BENCH_ITERS", "2000000"));

        // JIT warm-up (same chained shape as the timed loop).
        for (int i = 0; i < 20000; i++) {
            os.reset(out);
            Example.decode(blob).encodeTo(os);
        }

        // Chained round trip: decode the reference wire, then re-encode the freshly
        // decoded message (issue #86). sink keeps the re-encode live.
        long sink = 0;
        long t0 = cpuNanos();
        for (int i = 0; i < iters; i++) {
            os.reset(out);
            Example.decode(blob).encodeTo(os);
            sink += os.bytesUsed();
        }
        long t1 = cpuNanos();

        // Loop-path check: every re-encode had the reference length, and the last
        // one's bytes are the reference wire.
        if (sink != (long) serialized * iters
                || !Arrays.equals(out, 0, os.bytesUsed(), blob, 0, serialized)) {
            System.err.println("FAIL: sofab loop-path self-check");
            System.exit(1);
        }

        double cpu = (t1 - t0) / 1e9;
        double mbs = cpu > 0 ? (double) serialized * iters / cpu / 1e6 : 0.0;
        System.out.printf(
            "BENCH lang=java impl=sofab serialized_bytes=%d iters=%d "
            + "cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s%n",
            serialized, iters, cpu, mbs, sha);
    }
}
