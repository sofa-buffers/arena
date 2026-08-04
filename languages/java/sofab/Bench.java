// SofaBuffers Java benchmark target.
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the generated message.Example type, backed by the real corelib-java
// runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// Lives in package `message` so it can use the generated (package-private)
// Json.from(JsonObject, Example) from-jsonable helper.
//
// ONE source, TWO impls, selected by the BENCH_IMPL env var (#108):
//
//   sofab         encode() — one buffer the size of the whole message
//   sofab-stream  encodeTo(OStream) over a buffer SMALLER than the message with
//                 a FlushSink draining it as it fills, so the encode's memory
//                 need is the buffer and not the message
//
// The two paths are separate loops chosen before timing starts, never a branch
// inside the timed region. Only the ENCODE half differs; the decode stays the
// plain one-shot decode in both, so a row reflects one axis.
package message;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.Arrays;
import org.sofabuffers.sofab.OStream;

public class Bench {
    static String sha256hex(byte[] b) throws Exception {
        byte[] d = MessageDigest.getInstance("SHA-256").digest(b);
        StringBuilder sb = new StringBuilder(d.length * 2);
        for (byte x : d) sb.append(String.format("%02x", x & 0xFF));
        return sb.toString();
    }

    // The drained bytes land here so the loop keeps a live sink and the result
    // stays checkable against the reference wire. The encoder never sees this
    // array — only the FlushSink does.
    static final byte[] SINK = new byte[2048];
    static int sinkN = 0;

    /** An OStream whose buffer is `cap` bytes, draining into SINK as it fills. */
    static OStream streamOver(int cap) {
        return new OStream(new byte[cap], 0, (data, off, len) -> {
            System.arraycopy(data, off, SINK, sinkN, len);
            sinkN += len;
        });
    }

    /** Streaming encode of `m`; returns the number of bytes drained. */
    static int streamEncode(Example m, OStream os) throws Exception {
        sinkN = 0;
        m.encodeTo(os);   // serialize(os) + os.flush(), which also rewinds os
        return sinkN;
    }

    public static void main(String[] args) throws Exception {
        String path = System.getenv("STATE_JSON");
        String txt = new String(Files.readAllBytes(Paths.get(path)), StandardCharsets.UTF_8);
        JsonObject j = JsonParser.parseString(txt).getAsJsonObject();
        Example src = new Example();
        Json.from(j, src);

        String impl = System.getenv().getOrDefault("BENCH_IMPL", "sofab");
        boolean streaming = impl.equals("sofab-stream");
        int streamCap = Integer.parseInt(
            System.getenv().getOrDefault("STREAM_BUF_BYTES", "64"));

        // Warm-up round-trip + self-check (outside the timed region). The check
        // runs through whichever encode path this impl measures, so a dropped or
        // duplicated drained chunk fails here instead of being reported.
        byte[] blob = src.encode();
        int serialized = blob.length;
        String sha = sha256hex(blob);
        OStream os = streaming ? streamOver(streamCap) : null;
        boolean ok;
        if (streaming) {
            ok = streamEncode(Example.decode(blob), os) == serialized
                 && Arrays.equals(Arrays.copyOf(SINK, serialized), blob);
        } else {
            ok = Arrays.equals(Example.decode(blob).encode(), blob);
        }
        if (!ok) {
            System.err.println("FAIL: sofab round-trip self-check");
            System.exit(1);
        }

        int iters = Integer.parseInt(
            System.getenv().getOrDefault("BENCH_ITERS", "2000000"));

        // JIT warm-up (same chained shape as the timed loop).
        for (int i = 0; i < 20000; i++) {
            if (streaming) streamEncode(Example.decode(blob), os);
            else Example.decode(blob).encode();
        }

        // Chained round trip: decode the reference wire, then re-encode the freshly
        // decoded message (issue #86) — the proxy/transcode shape, which denies
        // protobuf its once-per-instance serialized-size memo so encode is measured
        // on equal terms. sink keeps the re-encode live and doubles as a loop-path
        // check (every re-encode is `serialized` bytes).
        //
        // Two loops, picked before t0: the impl must not cost a branch per
        // iteration that the other impl does not also pay.
        long sink = 0;
        long t0, t1;
        if (streaming) {
            t0 = System.nanoTime();
            for (int i = 0; i < iters; i++) {
                sink += streamEncode(Example.decode(blob), os);
            }
            t1 = System.nanoTime();
        } else {
            t0 = System.nanoTime();
            for (int i = 0; i < iters; i++) {
                sink += Example.decode(blob).encode().length;
            }
            t1 = System.nanoTime();
        }

        if (sink != (long) serialized * iters
            || (streaming && !Arrays.equals(Arrays.copyOf(SINK, serialized), blob))) {
            System.err.println("FAIL: sofab loop-path self-check");
            System.exit(1);
        }

        double cpu = (t1 - t0) / 1e9;
        double mbs = cpu > 0 ? (double) serialized * iters / cpu / 1e6 : 0.0;
        System.out.printf(
            "BENCH lang=java impl=%s serialized_bytes=%d iters=%d "
            + "cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s%n",
            impl, serialized, iters, cpu, mbs, sha);
    }
}
