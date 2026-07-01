// SofaBuffers Java benchmark target.
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the generated message.Example type, backed by the real corelib-java
// runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// Lives in package `message` so it can use the generated (package-private)
// Json.from(JsonObject, Example) from-jsonable helper.
package message;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.Arrays;

public class Bench {
    static String sha256hex(byte[] b) throws Exception {
        byte[] d = MessageDigest.getInstance("SHA-256").digest(b);
        StringBuilder sb = new StringBuilder(d.length * 2);
        for (byte x : d) sb.append(String.format("%02x", x & 0xFF));
        return sb.toString();
    }

    public static void main(String[] args) throws Exception {
        String path = System.getenv("STATE_JSON");
        String txt = new String(Files.readAllBytes(Paths.get(path)), StandardCharsets.UTF_8);
        JsonObject j = JsonParser.parseString(txt).getAsJsonObject();
        Example src = new Example();
        Json.from(j, src);

        // Warm-up round-trip + self-check (outside the timed region).
        byte[] blob = src.encode();
        int serialized = blob.length;
        String sha = sha256hex(blob);
        byte[] re = Example.decode(blob).encode();
        if (!Arrays.equals(re, blob)) {
            System.err.println("FAIL: sofab round-trip self-check");
            System.exit(1);
        }

        int iters = Integer.parseInt(
            System.getenv().getOrDefault("BENCH_ITERS", "2000000"));

        // JIT warm-up (outside the timed region).
        for (int i = 0; i < 20000; i++) {
            byte[] b = src.encode();
            Example.decode(b);
        }

        long t0 = System.nanoTime();
        for (int i = 0; i < iters; i++) {
            byte[] b = src.encode();
            Example.decode(b);
        }
        long t1 = System.nanoTime();

        double cpu = (t1 - t0) / 1e9;
        double mbs = cpu > 0 ? (double) serialized * iters / cpu / 1e6 : 0.0;
        System.out.printf(
            "BENCH lang=java impl=sofab serialized_bytes=%d iters=%d "
            + "cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s%n",
            serialized, iters, cpu, mbs, sha);
    }
}
