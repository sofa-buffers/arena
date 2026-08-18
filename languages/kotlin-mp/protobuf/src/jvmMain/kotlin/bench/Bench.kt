// Protobuf (Square Wire) Kotlin Multiplatform benchmark target.
// Encodes + decodes the canonical FullScaleExample message (hand-filled from
// schema/STATE.md) through Wire's generated Kotlin ProtoAdapters. Same message,
// same state, same timed region as the SofaBuffers impl of this row. Prints one
// uniform BENCH line (see docs/BENCH.md).
package bench

import fullscale.FullScaleExample
import fullscale.FullScaleSeqArrayOfStrings
import fullscale.FullScaleSeqStruct
import fullscale.FullScaleSeqStructOfArrays
import fullscale.FullScaleSeqStructOfFpArrays
import java.security.MessageDigest
import java.util.Locale
import okio.ByteString

private fun sha256hex(b: ByteArray): String {
    val d = MessageDigest.getInstance("SHA-256").digest(b)
    val sb = StringBuilder(d.size * 2)
    for (x in d) sb.append("0123456789abcdef"[(x.toInt() shr 4) and 0xF])
        .append("0123456789abcdef"[x.toInt() and 0xF])
    return sb.toString()
}

// proto3 has no narrow or unsigned integers: u8/u16/u32 ride in a uint32 field
// (Kotlin `Int`, read as unsigned by the UINT32 adapter) and u64 in a uint64
// field (`Long`), exactly as the Java/protobuf-java driver spells them.
private fun u32(v: Long): Int = v.toInt()
private fun u64(v: String): Long = v.toULong().toLong()

private fun build(): FullScaleExample {
    val nested = FullScaleSeqStruct(
        f32 = 3.14f,
        f64 = 3.14159265,
        str = "Hello, World!",
        bytes_field = ByteString.of(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte()),
    )

    val fpArrays = FullScaleSeqStructOfFpArrays(
        fp32 = listOf(1f, 2f, 3f, -Float.MAX_VALUE, Float.MAX_VALUE),
        fp64 = listOf(1.0, 2.0, 3.0, -Double.MAX_VALUE, Double.MAX_VALUE),
    )

    val arrays = FullScaleSeqStructOfArrays(
        u8 = listOf(0, 64, 128, 191, 255),
        i8 = listOf(-128, -64, 0, 63, 127),
        u16 = listOf(0, 16384, 32768, 49151, 65535),
        i16 = listOf(-32768, -16384, 0, 16383, 32767),
        u32 = listOf(u32(0L), u32(1073741824L), u32(2147483648L), u32(3221225471L), u32(4294967295L)),
        i32 = listOf(-2147483648, -1073741824, 0, 1073741823, 2147483647),
        u64 = listOf(
            0L,
            4611686018427387904L,
            u64("9223372036854775808"),
            u64("13835058055282163711"),
            u64("18446744073709551615"),
        ),
        i64 = listOf(
            -9223372036854775807L,
            -4611686018427387904L,
            0L,
            4611686018427387903L,
            9223372036854775807L,
        ),
        nested = fpArrays,
    )

    val strArr = FullScaleSeqArrayOfStrings(
        strings = listOf(
            "Hello, Sofab!",
            "",
            "1234567890",
            "äöüÄÖÜß",
            "This_is_a_very_long_test_string_with_!@#\$%^&*()_+-=[]{}",
        ),
    )

    return FullScaleExample(
        u8 = 200,
        i8 = -100,
        u16 = 50000,
        i16 = -20000,
        u32 = u32(3000000000L),
        i32 = -1000000000,
        u64 = 10000000000000L,
        i64 = -5000000000000L,
        nested = nested,
        arrays = arrays,
        string_array = strArr,
    )
}

public fun main() {
    val src = build()
    val adapter = FullScaleExample.ADAPTER

    // Warm-up round-trip + self-check (outside the timed region).
    val blob = adapter.encode(src)
    val serialized = blob.size
    val sha = sha256hex(blob)
    if (!adapter.encode(adapter.decode(blob)).contentEquals(blob)) {
        System.err.println("FAIL: protobuf round-trip self-check")
        kotlin.system.exitProcess(1)
    }

    val iters = (System.getenv("BENCH_ITERS") ?: "2000000").toInt()

    // JIT warm-up (same chained shape as the timed loop).
    for (i in 0 until 20000) {
        adapter.encode(adapter.decode(blob))
    }

    // Chained round trip: decode the reference wire, then re-encode the freshly
    // parsed message (issue #86) — the proxy/transcode shape. Each decode yields
    // a new message whose cached serialized size is unset, so protobuf pays the
    // size pass every encode instead of hitting a once-per-instance memo. sink
    // keeps the re-encode live and doubles as a loop-path check.
    var sink = 0L
    val t0 = System.nanoTime()
    for (i in 0 until iters) {
        sink += adapter.encode(adapter.decode(blob)).size.toLong()
    }
    val t1 = System.nanoTime()

    if (sink != serialized.toLong() * iters) {
        System.err.println("FAIL: protobuf loop-path self-check")
        kotlin.system.exitProcess(1)
    }

    val cpu = (t1 - t0) / 1e9
    val mbs = if (cpu > 0) serialized.toDouble() * iters / cpu / 1e6 else 0.0
    // Locale.ROOT: the runner parses these numbers, and a locale with a comma
    // decimal separator would hand it something it cannot read.
    println(
        String.format(
            Locale.ROOT,
            "BENCH lang=kotlin-mp impl=protobuf serialized_bytes=%d iters=%d " +
                "cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s",
            serialized, iters, cpu, mbs, sha,
        ),
    )
}
