// SofaBuffers Dart benchmark target (AOT-compiled).
//
// Encodes + decodes the canonical FullScaleExample message (schema/STATE.md)
// through the sofabgen-generated `Example` type, which is backed by the real
// corelib-dart runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// Built as a second entrypoint inside the generated project (alongside the
// generated `harness`), so it can `import 'package:harness/message.dart'` and
// reuse the generated serialize/decode directly. Run AOT-native (`dart compile
// exe`), never `dart run`/JIT — the fair comparison to the compiled ports
// (C/C++/Rust/Go), which also run native.
//
// Every schema-bounded field is generated as fixed-capacity inline storage
// (InlineString / InlineBytes / InlineXxxArray, sized from the schema), so the
// fill replaces contents in place — `assign` / `assignString` — instead of
// assigning a fresh List; only the string_array wrapper itself is a plain List,
// of InlineString elements. Same idiom the generated JSON harness uses.
//
// The u64 values above 2^63-1 are written as hex literals: Dart's native `int`
// is a 64-bit two's-complement value, and corelib-dart's writeUnsigned treats
// those bits as an unsigned varint — the exact convention the generated JSON
// filler uses (`BigInt.parse(...).toSigned(64).toInt()`). Hand-filled rather
// than parsed from state.json because Dart's JSON parser loses precision on
// integer literals above 2^63-1 (they fall back to double). The cross-language
// wire gate (sha256) catches any fill drift.

import 'dart:io';
import 'dart:typed_data';

import 'package:harness/message.dart';
import 'package:sofa_buffers_corelib/sofa_buffers_corelib.dart' as sofab;

import 'bench_common.dart';

Example buildExample() {
  return Example()
    ..u8 = 200
    ..i8 = -100
    ..u16 = 50000
    ..i16 = -20000
    ..u32 = 3000000000
    ..i32 = -1000000000
    ..u64 = 10000000000000
    ..i64 = -5000000000000
    ..nested.f32 = 3.14
    ..nested.f64 = 3.14159265
    ..nested.str.assignString('Hello, World!')
    ..nested.bytes_field.assign(<int>[0xDE, 0xAD, 0xBE, 0xEF])
    ..arrays.u8.assign(<int>[0, 64, 128, 191, 255])
    ..arrays.i8.assign(<int>[-128, -64, 0, 63, 127])
    ..arrays.u16.assign(<int>[0, 16384, 32768, 49151, 65535])
    ..arrays.i16.assign(<int>[-32768, -16384, 0, 16383, 32767])
    ..arrays.u32.assign(<int>[0, 1073741824, 2147483648, 3221225471, 4294967295])
    ..arrays.i32.assign(<int>[-2147483648, -1073741824, 0, 1073741823, 2147483647])
    ..arrays.u64.assign(<int>[
      0,
      0x4000000000000000, // 4611686018427387904
      0x8000000000000000, // 9223372036854775808
      0xBFFFFFFFFFFFFFFF, // 13835058055282163711
      0xFFFFFFFFFFFFFFFF, // 18446744073709551615
    ])
    ..arrays.i64.assign(<int>[
      -9223372036854775807,
      -4611686018427387904,
      0,
      4611686018427387903,
      9223372036854775807,
    ])
    ..arrays.nested.fp32.assign(
        <double>[1.0, 2.0, 3.0, -3.4028234663852886e38, 3.4028234663852886e38])
    ..arrays.nested.fp64.assign(
        <double>[1.0, 2.0, 3.0, -1.7976931348623157e308, 1.7976931348623157e308])
    ..string_array = <sofab.InlineString>[
      sofab.InlineString.of('Hello, Sofab!'),
      sofab.InlineString.of(''),
      sofab.InlineString.of('1234567890'),
      sofab.InlineString.of('äöüÄÖÜß'),
      sofab.InlineString.of(
          'This_is_a_very_long_test_string_with_!@#\$%^&*()_+-=[]{}'),
    ];
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  final src = buildExample();

  // Warm-up round-trip + self-check (outside the timed region).
  final blob = src.encode();
  final serialized = blob.length;
  final sha = sha256Hex(blob);
  final decoded = Example.decode(blob);
  if (!_bytesEqual(decoded.encode(), blob)) {
    stderr.writeln('FAIL: sofab round-trip self-check');
    exit(1);
  }

  final iters = int.tryParse(Platform.environment['BENCH_ITERS'] ?? '') ?? 2000000;

  // Chained round trip: decode the reference wire, then re-encode the freshly
  // decoded message (issue #86) — the proxy/transcode shape. `sink` is a
  // per-iteration data dependency so the round trip can't be optimized away.
  var sink = 0;
  final clock = CpuClock();
  final t0 = clock.seconds();
  for (var i = 0; i < iters; i++) {
    final dec = Example.decode(blob);
    final out = dec.encode();
    sink ^= out[0] ^ out.length;
  }
  final cpu = clock.seconds() - t0;

  final mbs = cpu > 0.0 ? serialized * iters / cpu / 1e6 : 0.0;
  // Keep `sink` observable so the loop body is not dead code.
  stderr.writeln('sink=$sink');
  stdout.writeln('BENCH lang=dart impl=sofab serialized_bytes=$serialized '
      'iters=$iters cpu_time_s=${cpu.toStringAsFixed(6)} '
      'throughput_mbs=${mbs.toStringAsFixed(2)} sha256=$sha');
}
