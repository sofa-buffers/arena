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

function encode(src: Example): Uint8Array {
  const os = new OStream();
  src.marshal(os);
  return os.bytes();
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
  const blob = encode(src);
  const serialized = blob.length;
  const sha = createHash("sha256").update(blob).digest("hex");
  const reencoded = encode(Example.decode(blob));
  if (reencoded.length !== blob.length || !blob.every((b, i) => b === reencoded[i])) {
    process.stderr.write("FAIL: sofab round-trip self-check\n");
    return 1;
  }

  const iters = parseInt(process.env.BENCH_ITERS ?? "500000", 10);

  // Pool a single OStream across encodes via reset() (corelib-ts) — the buffer
  // is hoisted out of the timed region, matching the bench contract and how
  // protobufjs internally reuses its writer.
  const os = new OStream();

  // Warm the JIT (same chained shape as the timed loop).
  for (let i = 0; i < 10000; i++) {
    os.reset();
    Example.decode(blob).marshal(os);
  }

  // Chained round trip: decode the reference wire, then re-encode the freshly
  // decoded message (issue #86) — the proxy/transcode shape, which denies
  // protobuf its once-per-instance serialized-size memo so encode is measured on
  // equal terms. sink keeps the re-encode live and doubles as a loop-path check
  // (every re-encode is `serialized` bytes).
  let sink = 0;
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < iters; i++) {
    os.reset();
    Example.decode(blob).marshal(os);
    sink += os.bytes().length;
  }
  const t1 = process.hrtime.bigint();

  if (sink !== serialized * iters) {
    process.stderr.write("FAIL: sofab loop-path self-check\n");
    return 1;
  }

  const cpu = Number(t1 - t0) / 1e9;
  const mbs = cpu > 0 ? (serialized * iters) / cpu / 1e6 : 0;
  process.stdout.write(
    `BENCH lang=typescript impl=sofab serialized_bytes=${serialized} ` +
      `iters=${iters} cpu_time_s=${cpu.toFixed(6)} ` +
      `throughput_mbs=${mbs.toFixed(2)} sha256=${sha}\n`,
  );
  return 0;
}

process.exit(main());
