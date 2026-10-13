// SofaBuffers TypeScript benchmark target.
//
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the generated `Example` type, backed by the real @sofa-buffers/corelib
// runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// This file is copied into the generated project (next to message.ts) by
// setup.sh so that `@sofa-buffers/corelib` and `./message.js` resolve.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { OStream } from "@sofa-buffers/corelib";
import { Example } from "./message.js";

// state.json stores u64/i64 as bare JSON number literals; the large ones
// (arrays.u64 / arrays.i64) exceed 2^53 and would lose precision under plain
// JSON.parse. Quote any 16+ digit integer literal so the generated fromJSON
// (which BigInt()s these fields) receives an exact value. Float literals are
// left untouched: their long digit runs are preceded by a '.', which the
// look-behind excludes, and small ints (< 16 digits) round-trip exactly.
function parseStatePreserveBigInts(text: string): Record<string, unknown> {
  const quoted = text.replace(/(?<![\d."])(-?\d{16,})(?![\d.])/g, '"$1"');
  return JSON.parse(quoted) as Record<string, unknown>;
}

// Process CPU time (user + system) in seconds — docs/BENCH.md rule 3. Same
// helper in both TypeScript drivers; process.cpuUsage() exists on Node and Bun.
function cpuSeconds(): number {
  const u = process.cpuUsage();
  return (u.user + u.system) / 1e6;
}

function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

function main(): number {
  const statePath = process.env.STATE_JSON;
  if (!statePath) {
    process.stderr.write("FAIL: STATE_JSON not set\n");
    return 1;
  }
  const state = parseStatePreserveBigInts(readFileSync(statePath, "utf8"));
  const src = Example.fromJSON(state);

  // Warm-up round-trip + self-check (outside the timed region).
  const blob = src.encode();
  const serialized = blob.length;
  const sha = createHash("sha256").update(blob).digest("hex");
  if (!sameBytes(Example.decode(blob).encode(), blob)) {
    process.stderr.write("FAIL: sofab round-trip self-check\n");
    return 1;
  }

  const iters = parseInt(process.env.BENCH_ITERS ?? "500000", 10);

  // One caller-owned OStream over a MAX_SIZE buffer, reused via reset();
  // os.bytes() is a view of the bytes written since the last reset().
  const os = new OStream(new Uint8Array(Example.MAX_SIZE));

  // Warm the JIT (same chained shape as the timed loop).
  for (let i = 0; i < 10000; i++) {
    os.reset();
    Example.decode(blob).serialize(os);
  }

  // Chained round trip: decode the reference wire, then re-encode the freshly
  // decoded message (issue #86) — the proxy/transcode shape, the same for both
  // impls. sink keeps the re-encode live; the loop-path check below also
  // compares the last re-encode's bytes against the reference.
  let sink = 0;
  const t0 = cpuSeconds();
  for (let i = 0; i < iters; i++) {
    os.reset();
    Example.decode(blob).serialize(os);
    sink += os.bytes().length;
  }
  const t1 = cpuSeconds();

  if (sink !== serialized * iters || !sameBytes(os.bytes(), blob)) {
    process.stderr.write("FAIL: sofab loop-path self-check\n");
    return 1;
  }

  const cpu = t1 - t0;
  const mbs = cpu > 0 ? (serialized * iters) / cpu / 1e6 : 0;
  process.stdout.write(
    `BENCH lang=typescript impl=sofab serialized_bytes=${serialized} ` +
      `iters=${iters} cpu_time_s=${cpu.toFixed(6)} ` +
      `throughput_mbs=${mbs.toFixed(2)} sha256=${sha}\n`,
  );
  return 0;
}

process.exit(main());
