// Protobuf Dart benchmark target (protoc_plugin / package:protobuf, AOT-compiled).
//
// Encodes + decodes the SAME FullScaleExample message with the SAME canonical
// values (schema/STATE.md), hand-filled. Same timed region + method as the
// SofaBuffers target. Prints one uniform BENCH line (see docs/BENCH.md). Run
// AOT-native (`dart compile exe`), never JIT — identical treatment to the sofab
// row so the comparison is fair.
//
// The opponent is the official Dart protobuf: `protoc-gen-dart` (protoc_plugin)
// generates gen/message.pb.dart against the `package:protobuf` runtime, the
// canonical, by-far-most-used protobuf implementation for Dart (the analogue of
// prost for Rust / protobuf-go for Go).
//
// 64-bit fields are `fixnum.Int64`; values above 2^63-1 are built from their
// hex bit-pattern (`Int64(0x8000000000000000)` == the unsigned wire value), the
// same two's-complement convention the sofab side uses. The wire gate (sha256)
// catches any fill drift.

import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'gen/message.pb.dart';
import 'bench_common.dart';

FullScaleExample build() {
  return FullScaleExample(
    u8: 200,
    i8: -100,
    u16: 50000,
    i16: -20000,
    u32: 3000000000,
    i32: -1000000000,
    u64: Int64(10000000000000),
    i64: Int64(-5000000000000),
    nested: FullScaleSeqStruct(
      f32: 3.14,
      f64: 3.14159265,
      str: 'Hello, World!',
      bytesField: <int>[0xDE, 0xAD, 0xBE, 0xEF],
    ),
    arrays: FullScaleSeqStructOfArrays(
      u8: <int>[0, 64, 128, 191, 255],
      i8: <int>[-128, -64, 0, 63, 127],
      u16: <int>[0, 16384, 32768, 49151, 65535],
      i16: <int>[-32768, -16384, 0, 16383, 32767],
      u32: <int>[0, 1073741824, 2147483648, 3221225471, 4294967295],
      i32: <int>[-2147483648, -1073741824, 0, 1073741823, 2147483647],
      u64: <Int64>[
        Int64(0),
        Int64(0x4000000000000000), // 4611686018427387904
        Int64(0x8000000000000000), // 9223372036854775808
        Int64(0xBFFFFFFFFFFFFFFF), // 13835058055282163711
        Int64(0xFFFFFFFFFFFFFFFF), // 18446744073709551615
      ],
      i64: <Int64>[
        Int64(-9223372036854775807),
        Int64(-4611686018427387904),
        Int64(0),
        Int64(4611686018427387903),
        Int64(9223372036854775807),
      ],
      nested: FullScaleSeqStructOfFpArrays(
        fp32: <double>[1.0, 2.0, 3.0, -3.4028234663852886e38, 3.4028234663852886e38],
        fp64: <double>[1.0, 2.0, 3.0, -1.7976931348623157e308, 1.7976931348623157e308],
      ),
    ),
    stringArray: FullScaleSeqArrayOfStrings(
      strings: <String>[
        'Hello, Sofab!',
        '',
        '1234567890',
        'äöüÄÖÜß',
        'This_is_a_very_long_test_string_with_!@#\$%^&*()_+-=[]{}',
      ],
    ),
  );
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  final src = build();

  // Warm-up round-trip + self-check (outside the timed region).
  final Uint8List blob = src.writeToBuffer();
  final serialized = blob.length;
  final sha = sha256Hex(blob);
  final decoded = FullScaleExample.fromBuffer(blob);
  if (!_bytesEqual(decoded.writeToBuffer(), blob)) {
    stderr.writeln('FAIL: protobuf round-trip self-check');
    exit(1);
  }

  final iters = int.tryParse(Platform.environment['BENCH_ITERS'] ?? '') ?? 2000000;

  // Chained round trip: decode the reference wire, then re-encode the freshly
  // decoded message (issue #86) — so encode runs on a just-parsed message
  // rather than a pre-built instance, denying protobuf its cached serialized
  // size. `sink` is a per-iteration data dependency against dead-code removal.
  var sink = 0;
  final clock = CpuClock();
  final t0 = clock.seconds();
  for (var i = 0; i < iters; i++) {
    final dec = FullScaleExample.fromBuffer(blob);
    final out = dec.writeToBuffer();
    sink ^= out[0] ^ out.length;
  }
  final cpu = clock.seconds() - t0;

  final mbs = cpu > 0.0 ? serialized * iters / cpu / 1e6 : 0.0;
  stderr.writeln('sink=$sink');
  stdout.writeln('BENCH lang=dart impl=protobuf serialized_bytes=$serialized '
      'iters=$iters cpu_time_s=${cpu.toStringAsFixed(6)} '
      'throughput_mbs=${mbs.toStringAsFixed(2)} sha256=$sha');
}
