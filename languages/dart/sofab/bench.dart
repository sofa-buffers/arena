// SofaBuffers Dart benchmark target (AOT-compiled).
//
// Encodes + decodes the canonical FullScaleExample message (schema/STATE.md)
// through the sofabgen-generated `Example` type, which is backed by the real
// corelib-dart runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// Built as a second entrypoint inside the generated project (alongside the
// generated `harness`), so it can `import 'package:harness/message.dart'` and
// reuse the generated marshal/decode directly. Run AOT-native (`dart compile
// exe`), never `dart run`/JIT — the fair comparison to the compiled ports
// (C/C++/Rust/Go), which also run native.
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
    ..nested = (ExampleNested()
      ..f32 = 3.14
      ..f64 = 3.14159265
      ..str = 'Hello, World!'
      ..bytes_field = Uint8List.fromList(<int>[0xDE, 0xAD, 0xBE, 0xEF]))
    ..arrays = (ExampleArrays()
      ..u8 = <int>[0, 64, 128, 191, 255]
      ..i8 = <int>[-128, -64, 0, 63, 127]
      ..u16 = <int>[0, 16384, 32768, 49151, 65535]
      ..i16 = <int>[-32768, -16384, 0, 16383, 32767]
      ..u32 = <int>[0, 1073741824, 2147483648, 3221225471, 4294967295]
      ..i32 = <int>[-2147483648, -1073741824, 0, 1073741823, 2147483647]
      ..u64 = <int>[
        0,
        0x4000000000000000, // 4611686018427387904
        0x8000000000000000, // 9223372036854775808
        0xBFFFFFFFFFFFFFFF, // 13835058055282163711
        0xFFFFFFFFFFFFFFFF, // 18446744073709551615
      ]
      ..i64 = <int>[
        -9223372036854775807,
        -4611686018427387904,
        0,
        4611686018427387903,
        9223372036854775807,
      ]
      ..nested = (ExampleArraysNested()
        ..fp32 = <double>[1.0, 2.0, 3.0, -3.4028234663852886e38, 3.4028234663852886e38]
        ..fp64 = <double>[1.0, 2.0, 3.0, -1.7976931348623157e308, 1.7976931348623157e308]))
    ..string_array = <String>[
      'Hello, Sofab!',
      '',
      '1234567890',
      'äöüÄÖÜß',
      'This_is_a_very_long_test_string_with_!@#\$%^&*()_+-=[]{}',
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
