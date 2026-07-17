// Protobuf Java benchmark target.
// Encodes + decodes the canonical FullScaleExample message (hand-filled from
// schema/STATE.md) through protobuf-java's generated builders. Same message,
// same state, same timed region as the SofaBuffers target. Prints one uniform
// BENCH line (see docs/BENCH.md).
package bench;

import com.google.protobuf.ByteString;
import fullscale.Message.FullScaleExample;
import fullscale.Message.FullScaleSeqStruct;
import fullscale.Message.FullScaleSeqStructOfArrays;
import fullscale.Message.FullScaleSeqStructOfFpArrays;
import fullscale.Message.FullScaleSeqArrayOfStrings;
import java.security.MessageDigest;
import java.util.Arrays;

public class Bench {
    static String sha256hex(byte[] b) throws Exception {
        byte[] d = MessageDigest.getInstance("SHA-256").digest(b);
        StringBuilder sb = new StringBuilder(d.length * 2);
        for (byte x : d) sb.append(String.format("%02x", x & 0xFF));
        return sb.toString();
    }

    static FullScaleExample build() {
        FullScaleSeqStruct nested = FullScaleSeqStruct.newBuilder()
            .setF32(3.14f)
            .setF64(3.14159265)
            .setStr("Hello, World!")
            .setBytesField(ByteString.copyFrom(
                new byte[]{(byte) 0xDE, (byte) 0xAD, (byte) 0xBE, (byte) 0xEF}))
            .build();

        FullScaleSeqStructOfFpArrays fpArrays = FullScaleSeqStructOfFpArrays.newBuilder()
            .addFp32(1f).addFp32(2f).addFp32(3f)
            .addFp32(-Float.MAX_VALUE).addFp32(Float.MAX_VALUE)
            .addFp64(1d).addFp64(2d).addFp64(3d)
            .addFp64(-Double.MAX_VALUE).addFp64(Double.MAX_VALUE)
            .build();

        FullScaleSeqStructOfArrays arrays = FullScaleSeqStructOfArrays.newBuilder()
            .addU8(0).addU8(64).addU8(128).addU8(191).addU8(255)
            .addI8(-128).addI8(-64).addI8(0).addI8(63).addI8(127)
            .addU16(0).addU16(16384).addU16(32768).addU16(49151).addU16(65535)
            .addI16(-32768).addI16(-16384).addI16(0).addI16(16383).addI16(32767)
            .addU32(0).addU32(1073741824)
            .addU32((int) 2147483648L).addU32((int) 3221225471L).addU32((int) 4294967295L)
            .addI32(-2147483648).addI32(-1073741824).addI32(0)
            .addI32(1073741823).addI32(2147483647)
            .addU64(0L).addU64(4611686018427387904L)
            .addU64(Long.parseUnsignedLong("9223372036854775808"))
            .addU64(Long.parseUnsignedLong("13835058055282163711"))
            .addU64(Long.parseUnsignedLong("18446744073709551615"))
            .addI64(-9223372036854775807L).addI64(-4611686018427387904L).addI64(0L)
            .addI64(4611686018427387903L).addI64(9223372036854775807L)
            .setNested(fpArrays)
            .build();

        FullScaleSeqArrayOfStrings strArr = FullScaleSeqArrayOfStrings.newBuilder()
            .addStrings("Hello, Sofab!")
            .addStrings("")
            .addStrings("1234567890")
            .addStrings("äöüÄÖÜß")
            .addStrings("This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}")
            .build();

        return FullScaleExample.newBuilder()
            .setU8(200)
            .setI8(-100)
            .setU16(50000)
            .setI16(-20000)
            .setU32((int) 3000000000L)
            .setI32(-1000000000)
            .setU64(10000000000000L)
            .setI64(-5000000000000L)
            .setNested(nested)
            .setArrays(arrays)
            .setStringArray(strArr)
            .build();
    }

    public static void main(String[] args) throws Exception {
        FullScaleExample src = build();

        // Warm-up round-trip + self-check (outside the timed region).
        byte[] blob = src.toByteArray();
        int serialized = blob.length;
        String sha = sha256hex(blob);
        byte[] re = FullScaleExample.parseFrom(blob).toByteArray();
        if (!Arrays.equals(re, blob)) {
            System.err.println("FAIL: protobuf round-trip self-check");
            System.exit(1);
        }

        int iters = Integer.parseInt(
            System.getenv().getOrDefault("BENCH_ITERS", "2000000"));

        // JIT warm-up (same chained shape as the timed loop).
        for (int i = 0; i < 20000; i++) {
            FullScaleExample.parseFrom(blob).toByteArray();
        }

        // Chained round trip: decode the reference wire, then re-encode the freshly
        // parsed message (issue #86) — the proxy/transcode shape. Each parseFrom
        // yields a new message whose memoized serialized size is unset, so protobuf
        // pays the size pass every encode instead of hitting a once-per-instance
        // memo. sink keeps the re-encode live and doubles as a loop-path check.
        long sink = 0;
        long t0 = System.nanoTime();
        for (int i = 0; i < iters; i++) {
            sink += FullScaleExample.parseFrom(blob).toByteArray().length;
        }
        long t1 = System.nanoTime();

        if (sink != (long) serialized * iters) {
            System.err.println("FAIL: protobuf loop-path self-check");
            System.exit(1);
        }

        double cpu = (t1 - t0) / 1e9;
        double mbs = cpu > 0 ? (double) serialized * iters / cpu / 1e6 : 0.0;
        System.out.printf(
            "BENCH lang=java impl=protobuf serialized_bytes=%d iters=%d "
            + "cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s%n",
            serialized, iters, cpu, mbs, sha);
    }
}
