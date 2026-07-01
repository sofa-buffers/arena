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
  const reencoded = Type.encode(Type.decode(blob)).finish();
  if (reencoded.length !== blob.length || !blob.every((b, i) => b === reencoded[i])) {
    process.stderr.write("FAIL: protobuf round-trip self-check\n");
    return 1;
  }

  const iters = parseInt(process.env.BENCH_ITERS ?? "500000", 10);

  // Warm the JIT.
  for (let i = 0; i < 10000; i++) {
    Type.decode(Type.encode(src).finish());
  }

  const t0 = process.hrtime.bigint();
  for (let i = 0; i < iters; i++) {
    Type.decode(Type.encode(src).finish());
  }
  const t1 = process.hrtime.bigint();

  const cpu = Number(t1 - t0) / 1e9;
  const mbs = cpu > 0 ? (serialized * iters) / cpu / 1e6 : 0;
  process.stdout.write(
    `BENCH lang=typescript impl=protobuf serialized_bytes=${serialized} ` +
      `iters=${iters} cpu_time_s=${cpu.toFixed(6)} ` +
      `throughput_mbs=${mbs.toFixed(2)} sha256=${sha}\n`,
  );
  return 0;
}

main().then((c) => process.exit(c));
