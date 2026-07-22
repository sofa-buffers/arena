// Shared benchmark support for BOTH Dart impls (sofab + protobuf).
//
// setup.sh copies this verbatim next to each driver so the two impls use the
// IDENTICAL timing clock and checksum — the fairness core (docs/BENCH.md): a
// helper difference between impls would bias the comparison. Nothing in here is
// on the timed hot path; the SHA-256 and the clock reads happen only in the
// warm-up / reporting region.

import 'dart:io';
import 'dart:typed_data';

/// Process CPU time in seconds (docs/BENCH.md: measure over process/thread CPU
/// time, never wall-clock, so a busy host doesn't skew the number). On Linux we
/// read `utime`+`stime` from `/proc/self/stat` (clock ticks, USER_HZ = 100);
/// elsewhere we fall back to a wall-clock [Stopwatch]. Copied from
/// corelib-dart/bench/cpu_time.dart so the arena target measures like the
/// upstream Dart benchmarks.
class CpuClock {
  CpuClock() : _linux = Platform.isLinux {
    if (!_linux) _sw.start();
  }

  final bool _linux;
  final Stopwatch _sw = Stopwatch();
  static const double _userHz = 100.0;

  double seconds() {
    if (!_linux) return _sw.elapsedMicroseconds / 1e6;
    final stat = File('/proc/self/stat').readAsStringSync();
    // Fields after the final ')' (comm may contain spaces/parens): field 3
    // (state) onward. utime = field 14, stime = field 15.
    final rest = stat.substring(stat.lastIndexOf(')') + 2).trim();
    final parts = rest.split(RegExp(r'\s+'));
    final utime = int.parse(parts[11]);
    final stime = int.parse(parts[12]);
    return (utime + stime) / _userHz;
  }
}

/// Lowercase-hex SHA-256 of [message] — the wire checksum the cross-language
/// gate compares (run_benchmark.sh REF_SOFAB_SHA / REF_PROTO_SHA). A pure-Dart
/// FIPS-180-4 implementation so the arena needs no third-party crypto package
/// for what is only a gate checksum; it runs once per process, outside timing.
String sha256Hex(List<int> message) {
  const List<int> k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  const int mask = 0xFFFFFFFF;
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & mask;

  var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

  // Padding: append 0x80, then zeros, then the 64-bit big-endian bit length.
  final int len = message.length;
  final int bitLen = len * 8;
  final int padded = ((len + 8) ~/ 64 + 1) * 64;
  final msg = Uint8List(padded);
  msg.setRange(0, len, message);
  msg[len] = 0x80;
  for (var i = 0; i < 8; i++) {
    msg[padded - 1 - i] = (bitLen >> (8 * i)) & 0xFF;
  }

  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < padded; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final j = chunk + i * 4;
      w[i] = (msg[j] << 24) | (msg[j + 1] << 16) | (msg[j + 2] << 8) | msg[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & mask;
    }

    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final t1 = (h + s1 + ch + k[i] + w[i]) & mask;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & mask;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & mask;
    }

    h0 = (h0 + a) & mask;
    h1 = (h1 + b) & mask;
    h2 = (h2 + c) & mask;
    h3 = (h3 + d) & mask;
    h4 = (h4 + e) & mask;
    h5 = (h5 + f) & mask;
    h6 = (h6 + g) & mask;
    h7 = (h7 + h) & mask;
  }

  final sb = StringBuffer();
  for (final v in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
    sb.write(v.toRadixString(16).padLeft(8, '0'));
  }
  return sb.toString();
}
