/// Unit tests for [PathParser].
///
/// Covers parsePath, parsePathWithRemainder, readUint32BE,
/// and PathParseResult.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/path_parser.dart';

/// Helper: build derivation path data from a depth and component list.
/// Each component is the raw 32-bit value (with hardened bit if applicable).
Uint8List _buildPathData(int depth, List<int> components) {
  final bytes = Uint8List(1 + depth * 4);
  bytes[0] = depth;
  for (int i = 0; i < depth; i++) {
    final offset = 1 + i * 4;
    final value = components[i];
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }
  return bytes;
}

void main() {
  // ═════════════════════════════════════════════════════════════════════
  // readUint32BE
  // ═════════════════════════════════════════════════════════════════════

  group('readUint32BE', () {
    test('reads known byte sequence (0x00000000)', () {
      final data = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      expect(PathParser.readUint32BE(data, 0), 0);
    });

    test('reads known byte sequence (0xFFFFFFFF)', () {
      final data = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      expect(PathParser.readUint32BE(data, 0), 0xFFFFFFFF);
    });

    test('reads known byte sequence (0x8000002C = 44 hardened)', () {
      final data = Uint8List.fromList([0x80, 0x00, 0x00, 0x2C]);
      expect(PathParser.readUint32BE(data, 0), 0x8000002C);
    });

    test('reads known byte sequence (0x00000000 at offset 2)', () {
      final data = Uint8List.fromList([0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00]);
      expect(PathParser.readUint32BE(data, 2), 0);
    });

    test('reads known byte sequence (0x0000003C = 60)', () {
      final data = Uint8List.fromList([0x00, 0x00, 0x00, 0x3C]);
      expect(PathParser.readUint32BE(data, 0), 0x0000003C);
    });

    test('reads known byte sequence (0x80000000 = 0 hardened)', () {
      final data = Uint8List.fromList([0x80, 0x00, 0x00, 0x00]);
      expect(PathParser.readUint32BE(data, 0), 0x80000000);
    });

    test('reads known byte sequence (0x00000001 = 1)', () {
      final data = Uint8List.fromList([0x00, 0x00, 0x00, 0x01]);
      expect(PathParser.readUint32BE(data, 0), 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // parsePath
  // ═════════════════════════════════════════════════════════════════════

  group('parsePath', () {
    test('returns null for null input', () {
      expect(PathParser.parsePath(null), isNull);
    });

    test('returns null for empty data', () {
      expect(PathParser.parsePath(Uint8List(0)), isNull);
    });

    test('parses standard Ethereum path m/44\'/60\'/0\'/0/0', () {
      // depth=5, components: 44', 60', 0', 0, 0
      final data = _buildPathData(5, [
        0x8000002C, // 44 hardened
        0x8000003C, // 60 hardened
        0x80000000, // 0 hardened
        0x00000000, // 0 non-hardened
        0x00000000, // 0 non-hardened
      ]);

      final result = PathParser.parsePath(data);
      expect(result, "m/44'/60'/0'/0/0");
    });

    test('parses Solana path m/44\'/501\'/0\'', () {
      // depth=3, components: 44', 501', 0'
      final data = _buildPathData(3, [
        0x8000002C, // 44 hardened
        0x800001F5, // 501 hardened
        0x80000000, // 0 hardened
      ]);

      final result = PathParser.parsePath(data);
      expect(result, "m/44'/501'/0'");
    });

    test('parses Bitcoin path m/84\'/0\'/0\'/0/0', () {
      // depth=5, components: 84', 0', 0', 0, 0
      final data = _buildPathData(5, [
        0x80000054, // 84 hardened
        0x80000000, // 0 hardened
        0x80000000, // 0 hardened
        0x00000000, // 0 non-hardened
        0x00000000, // 0 non-hardened
      ]);

      final result = PathParser.parsePath(data);
      expect(result, "m/84'/0'/0'/0/0");
    });

    test('parses path with all non-hardened components', () {
      final data = _buildPathData(3, [
        0x00000000, // 0
        0x00000001, // 1
        0x00000002, // 2
      ]);

      final result = PathParser.parsePath(data);
      expect(result, 'm/0/1/2');
    });

    test('returns null when depth > 10 (sanity check)', () {
      // depth=11 exceeds max
      final data = Uint8List(1 + 11 * 4);
      data[0] = 11;
      expect(PathParser.parsePath(data), isNull);
    });

    test('returns null when data is too short for declared depth', () {
      // depth=5 but only 1+3*4 = 13 bytes (need 1+5*4=21)
      final data = Uint8List(1 + 3 * 4);
      data[0] = 5;
      expect(PathParser.parsePath(data), isNull);
    });

    test('parses single-component path (depth=1)', () {
      final data = _buildPathData(1, [0x80000000]); // 0'
      final result = PathParser.parsePath(data);
      expect(result, "m/0'");
    });

    test('parses path with mixed hardened/non-hardened at any position', () {
      // depth=4: 44', 60', 0, 0 (last two non-hardened)
      final data = _buildPathData(4, [
        0x8000002C, // 44'
        0x8000003C, // 60'
        0x00000000, // 0
        0x00000000, // 0
      ]);
      final result = PathParser.parsePath(data);
      expect(result, "m/44'/60'/0/0");
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // stripNumSignersPrefix
  // ═════════════════════════════════════════════════════════════════════

  group('stripNumSignersPrefix', () {
    test('strips leading num_signers byte when followed by plausible count', () {
      // Real OKX Solana frame: 01 (num_signers) then path depth 04.
      final data = Uint8List.fromList([0x01, 0x04, 0x80, 0x00, 0x00, 0x2C]);
      final stripped = PathParser.stripNumSignersPrefix(data);
      expect(stripped, equals(Uint8List.fromList([0x04, 0x80, 0x00, 0x00, 0x2C])));
    });

    test('leaves standard frames untouched (depth=4 first byte)', () {
      final data = Uint8List.fromList([0x04, 0x80, 0x00, 0x00, 0x2C]);
      expect(PathParser.stripNumSignersPrefix(data), equals(data));
    });

    test('does not strip when second byte is outside 2..5', () {
      final data = Uint8List.fromList([0x01, 0x06, 0x80, 0x00]);
      expect(PathParser.stripNumSignersPrefix(data), equals(data));
    });

    test('does not strip a single-byte payload', () {
      final data = Uint8List.fromList([0x01]);
      expect(PathParser.stripNumSignersPrefix(data), equals(data));
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // parsePathWithRemainder
  // ═════════════════════════════════════════════════════════════════════

  group('parsePathWithRemainder', () {
    test('returns null for empty data', () {
      expect(PathParser.parsePathWithRemainder(Uint8List(0)), isNull);
    });

    test('returns path and empty remainder when no extra data', () {
      final pathData = _buildPathData(2, [0x8000002C, 0x8000003C]); // 44'/60'
      final result = PathParser.parsePathWithRemainder(pathData);
      expect(result, isNotNull);
      expect(result!.path, "m/44'/60'");
      expect(result.remainder, isEmpty);
    });

    test('returns path and remainder when extra data exists', () {
      final pathData = _buildPathData(1, [0x80000000]); // 0'
      final extra = Uint8List.fromList([0xAB, 0xCD, 0xEF]);
      final combined = Uint8List(pathData.length + extra.length);
      combined.setRange(0, pathData.length, pathData);
      combined.setRange(pathData.length, combined.length, extra);

      final result = PathParser.parsePathWithRemainder(combined);
      expect(result, isNotNull);
      expect(result!.path, "m/0'");
      expect(result.remainder, equals(extra));
    });

    test('returns null when depth > 10', () {
      final data = Uint8List(1 + 11 * 4);
      data[0] = 11;
      expect(PathParser.parsePathWithRemainder(data), isNull);
    });

    test('returns null when data too short for declared depth', () {
      final data = Uint8List(3);
      data[0] = 5;
      expect(PathParser.parsePathWithRemainder(data), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // PathParseResult
  // ═════════════════════════════════════════════════════════════════════

  group('PathParseResult', () {
    test('construction stores path and remainder', () {
      final remainder = Uint8List.fromList([0x01, 0x02]);
      final result = PathParseResult("m/44'/60'/0'/0/0", remainder);
      expect(result.path, "m/44'/60'/0'/0/0");
      expect(result.remainder, equals(remainder));
    });

    test('constructor works', () {
      final result = PathParseResult('m/0', Uint8List(0));
      expect(result.path, 'm/0');
      expect(result.remainder, isEmpty);
    });
  });
}
