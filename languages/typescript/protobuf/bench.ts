// Protobuf TypeScript benchmark target.
//
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through protobufjs, loading schema/message.proto at runtime. Same message,
// same state, same timed region as the SofaBuffers target. Prints one uniform
// BENCH line (see docs/BENCH.md).
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import protobuf from "protobufjs";

// state.json stores u64/i64 as bare JSON number literals; the large ones exceed
// 2^53 and would lose precision under plain JSON.parse. Quote any 16+ digit
// integer literal so protobufjs receives an exact (string) value for its 64-bit
// fields. Float literals are untouched (their digit runs are preceded by '.').
function parseStatePreserveBigInts(text: string): Record<string, any> {
  const quoted = text.replace(/(?<![\d."])(-?\d{16,})(?![\d.])/g, '"$1"');
  return JSON.parse(quoted);
}

function build(state: Record<string, any>): Record<string, unknown> {
  const n = state.nested;
  const a = state.arrays;
  return {
    u8: state.u8, i8: state.i8, u16: state.u16, i16: state.i16,
    u32: state.u32, i32: state.i32, u64: state.u64, i64: state.i64,
    nested: {
      f32: n.f32,
      f64: n.f64,
      str: n.str,
      // protobufjs camelCases proto field names by default.
      bytesField: new Uint8Array(n.bytes_field),
    },
    arrays: {
      u8: a.u8, i8: a.i8, u16: a.u16, i16: a.i16,
      u32: a.u32, i32: a.i32, u64: a.u64, i64: a.i64,
      nested: { fp32: a.nested.fp32, fp64: a.nested.fp64 },
    },
    stringArray: { strings: state.string_array },
  };
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

async function main(): Promise<number> {
  const statePath = process.env.STATE_JSON;
  const protoPath = process.env.PROTO_PATH;
  if (!statePath || !protoPath) {
    process.stderr.write("FAIL: STATE_JSON / PROTO_PATH not set\n");
    return 1;
  }
  const root = await protobuf.load(protoPath);
  const Type = root.lookupType("fullscale.FullScaleExample");

  const state = parseStatePreserveBigInts(readFileSync(statePath, "utf8"));
  const payload = build(state);
  // fromObject coerces string 64-bit literals into Long, preserving exact
  // values beyond 2^53 (Type.verify would reject the string form).
  const src = Type.fromObject(payload);

  // Warm-up round-trip + self-check (outside the timed region).
  const blob = Type.encode(src).finish();
  const serialized = blob.length;
  const sha = createHash("sha256").update(blob).digest("hex");
  if (!sameBytes(Type.encode(Type.decode(blob)).finish(), blob)) {
    process.stderr.write("FAIL: protobuf round-trip self-check\n");
    return 1;
  }

  const iters = parseInt(process.env.BENCH_ITERS ?? "500000", 10);

  // One Writer reused via reset() (pos back to 0, grown buffer kept);
  // finish(true) returns a view of the written bytes instead of a copy.
  const w = protobuf.Writer.create();

  // Warm the JIT (same chained shape as the timed loop).
  for (let i = 0; i < 10000; i++) {
    w.reset();
    Type.encode(Type.decode(blob), w);
  }

  // Chained round trip: decode the reference wire, then re-encode the freshly
  // decoded message (issue #86) — the proxy/transcode shape, so encode runs on a
  // just-parsed message rather than a pre-built, reused one. sink keeps the
  // re-encode live; the loop-path check below also compares the last
  // re-encode's bytes against the reference.
  let sink = 0;
  const t0 = cpuSeconds();
  for (let i = 0; i < iters; i++) {
    w.reset();
    Type.encode(Type.decode(blob), w);
    sink += w.finish(true).length;
  }
  const t1 = cpuSeconds();

  if (sink !== serialized * iters || !sameBytes(w.finish(true), blob)) {
    process.stderr.write("FAIL: protobuf loop-path self-check\n");
    return 1;
  }

  const cpu = t1 - t0;
  const mbs = cpu > 0 ? (serialized * iters) / cpu / 1e6 : 0;
  process.stdout.write(
    `BENCH lang=typescript impl=protobuf serialized_bytes=${serialized} ` +
      `iters=${iters} cpu_time_s=${cpu.toFixed(6)} ` +
      `throughput_mbs=${mbs.toFixed(2)} sha256=${sha}\n`,
  );
  return 0;
}

main().then((c) => process.exit(c));
