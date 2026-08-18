// SofaBuffers Kotlin Multiplatform benchmark target.
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the generated message.Example type, backed by the real
// corelib-kotlin-mp runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// Lives in package `message` — and in this module — so it can use the generated
// (internal) JsonValue/Json from-jsonable helper of commonMain.
package message

import java.nio.file.Files
import java.nio.file.Paths
import java.security.MessageDigest
import java.util.Locale

private fun sha256hex(b: ByteArray): String {
    val d = MessageDigest.getInstance("SHA-256").digest(b)
    val sb = StringBuilder(d.size * 2)
    for (x in d) sb.append("0123456789abcdef"[(x.toInt() shr 4) and 0xF])
        .append("0123456789abcdef"[x.toInt() and 0xF])
    return sb.toString()
}

public fun main() {
    val path = System.getenv("STATE_JSON")
    val txt = String(Files.readAllBytes(Paths.get(path)), Charsets.UTF_8)
    val src = Example()
    Json.from(JsonValue.parse(txt).obj(), src)

    // Warm-up round-trip + self-check (outside the timed region).
    val blob = src.encode()
    val serialized = blob.size
    val sha = sha256hex(blob)
    if (!Example.decode(blob).encode().contentEquals(blob)) {
        System.err.println("FAIL: sofab round-trip self-check")
        kotlin.system.exitProcess(1)
    }

    val iters = (System.getenv("BENCH_ITERS") ?: "2000000").toInt()

    // JIT warm-up (same chained shape as the timed loop).
    for (i in 0 until 20000) {
        Example.decode(blob).encode()
    }

    // Chained round trip: decode the reference wire, then re-encode the freshly
    // decoded message (issue #86) — the proxy/transcode shape, which denies
    // protobuf its once-per-instance serialized-size memo so encode is measured
    // on equal terms. sink keeps the re-encode live and doubles as a loop-path
    // check (every re-encode is `serialized` bytes).
    var sink = 0L
    val t0 = System.nanoTime()
    for (i in 0 until iters) {
        sink += Example.decode(blob).encode().size.toLong()
    }
    val t1 = System.nanoTime()

    if (sink != serialized.toLong() * iters) {
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
