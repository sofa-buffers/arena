// SofaBuffers Kotlin Multiplatform benchmark target.
// Encodes + decodes the canonical FullScaleExample message (hand-filled from
// schema/STATE.md) through the generated message.Example type, backed by the
// real corelib-kotlin-mp runtime. Same message, same state, same timed region
// as the protobuf impl of this row. Prints one uniform BENCH line (see
// docs/BENCH.md).
@file:OptIn(ExperimentalUnsignedTypes::class)

package bench

import java.lang.management.ManagementFactory
import java.security.MessageDigest
import java.util.Arrays
import java.util.Locale
import message.Example
import org.sofabuffers.sofab.OStream

private fun sha256hex(b: ByteArray): String {
    val d = MessageDigest.getInstance("SHA-256").digest(b)
    val sb = StringBuilder(d.size * 2)
    for (x in d) sb.append("0123456789abcdef"[(x.toInt() shr 4) and 0xF])
        .append("0123456789abcdef"[x.toInt() and 0xF])
    return sb.toString()
}

private fun cpuNanos(): Long =
    (ManagementFactory.getOperatingSystemMXBean() as com.sun.management.OperatingSystemMXBean)
        .processCpuTime

private fun build(): Example {
    val m = Example()
    m.u8 = 200u
    m.i8 = -100
    m.u16 = 50000u
    m.i16 = -20000
    m.u32 = 3000000000u
    m.i32 = -1000000000
    m.u64 = 10000000000000uL
    m.i64 = -5000000000000L

    m.nested.f32 = 3.14f
    m.nested.f64 = 3.14159265
    m.nested.str = "Hello, World!"
    m.nested.bytes_field = byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte())

    val a = m.arrays
    a.u8 = ubyteArrayOf(0u, 64u, 128u, 191u, 255u)
    a.i8 = byteArrayOf(-128, -64, 0, 63, 127)
    a.u16 = ushortArrayOf(0u, 16384u, 32768u, 49151u, 65535u)
    a.i16 = shortArrayOf(-32768, -16384, 0, 16383, 32767)
    a.u32 = uintArrayOf(0u, 1073741824u, 2147483648u, 3221225471u, 4294967295u)
    a.i32 = intArrayOf(-2147483648, -1073741824, 0, 1073741823, 2147483647)
    a.u64 = ulongArrayOf(
        0uL,
        4611686018427387904uL,
        9223372036854775808uL,
        13835058055282163711uL,
        18446744073709551615uL,
    )
    a.i64 = longArrayOf(
        -9223372036854775807L,
        -4611686018427387904L,
        0L,
        4611686018427387903L,
        9223372036854775807L,
    )
    a.nested.fp32 = floatArrayOf(1f, 2f, 3f, -Float.MAX_VALUE, Float.MAX_VALUE)
    a.nested.fp64 = doubleArrayOf(1.0, 2.0, 3.0, -Double.MAX_VALUE, Double.MAX_VALUE)

    m.string_array = mutableListOf(
        "Hello, Sofab!",
        "",
        "1234567890",
        "äöüÄÖÜß",
        "This_is_a_very_long_test_string_with_!@#\$%^&*()_+-=[]{}",
    )
    return m
}

public fun main() {
    // Caller-owned output buffer + encoder, hoisted out of the timed loop.
    val out = ByteArray(Example.MAX_SIZE)
    val os = OStream(out)

    // Warm-up round-trip + self-check (outside the timed region).
    build().encodeTo(os)
    val blob = out.copyOf(os.bytesUsed)
    val serialized = blob.size
    val sha = sha256hex(blob)
    os.reset(out)
    Example.decode(blob).encodeTo(os)
    if (!Arrays.equals(out, 0, os.bytesUsed, blob, 0, serialized)) {
        System.err.println("FAIL: sofab round-trip self-check")
        kotlin.system.exitProcess(1)
    }

    val iters = (System.getenv("BENCH_ITERS") ?: "2000000").toInt()

    // JIT warm-up (same chained shape as the timed loop).
    for (i in 0 until 20000) {
        os.reset(out)
        Example.decode(blob).encodeTo(os)
    }

    // Chained round trip: decode the reference wire, then re-encode the freshly
    // decoded message (issue #86). sink keeps the re-encode live.
    //
    // decode(), not the generated tryDecode(data, out): this row was measured both
    // ways and the reused destination landed inside its own best-of-5 spread, so
    // docs/BENCH.md rule 6 keeps the library's documented one-shot. Square Wire
    // generates immutable messages too, so adapter.decode has no destination to
    // reuse and the baseline could not follow either.
    var sink = 0L
    val t0 = cpuNanos()
    for (i in 0 until iters) {
        os.reset(out)
        Example.decode(blob).encodeTo(os)
        sink += os.bytesUsed.toLong()
    }
    val t1 = cpuNanos()

    // Loop-path check: every re-encode had the reference length, and the last
    // one's bytes are the reference wire.
    if (sink != serialized.toLong() * iters ||
        !Arrays.equals(out, 0, os.bytesUsed, blob, 0, serialized)
    ) {
        System.err.println("FAIL: sofab loop-path self-check")
        kotlin.system.exitProcess(1)
    }

    val cpu = (t1 - t0) / 1e9
    val mbs = if (cpu > 0) serialized.toDouble() * iters / cpu / 1e6 else 0.0
    // Locale.ROOT: the runner parses these numbers, and a locale with a comma
    // decimal separator would hand it something it cannot read.
    println(
        String.format(
            Locale.ROOT,
            "BENCH lang=kotlin-mp impl=sofab serialized_bytes=%d iters=%d " +
                "cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s",
            serialized, iters, cpu, mbs, sha,
        ),
    )
}
