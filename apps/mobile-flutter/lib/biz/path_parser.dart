import 'dart:typed_data';

/// Parses BIP-32/SLIP-10 derivation paths from Ledger APDU wire format.
///
/// Wire format: `[depth(1B)] [component_0(4B BE)] ... [component_N(4B BE)]`
/// Bit 31 (`0x80000000`) of each component indicates hardened derivation.
///
/// Consolidated from [AppState._extractPathFromData] and
/// [ApduHandler._parseDerivationPath] which were duplicate implementations.
class PathParser {
  PathParser._();

  /// Read a big-endian 32-bit unsigned integer from [data] at [offset].
  static int readUint32BE(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  /// Parse a BIP-32 derivation path string from the beginning of [data].
  ///
  /// Returns the path string (e.g. `"m/44'/60'/0'/0/0"`) or `null` if
  /// the data is invalid.
  static String? parsePath(Uint8List? data) {
    if (data == null || data.isEmpty) return null;

    final depth = data[0];
    if (depth > 10) return null; // sanity check
    final expectedLen = 1 + depth * 4;
    if (data.length < expectedLen) return null;

    final components = <String>['m'];
    for (int i = 0; i < depth; i++) {
      final offset = 1 + i * 4;
      final value = readUint32BE(data, offset);
      final isHardened = (value & 0x80000000) != 0;
      final index = value & 0x7FFFFFFF;
      components.add(isHardened ? "$index'" : '$index');
    }

    return components.join('/');
  }

  /// Strip the OKX Solana `num_signers` prefix from [data] if present.
  ///
  /// OKX prefixes the first Solana signing frame (P1=0x01) with a single
  /// `num_signers` byte before the BIP32 path. Standard Ledger clients omit
  /// it. Heuristic (mirrors `packages/apdu/src/handlers/sol.ts`): a leading
  /// `0x01` followed by a plausible signer count (2..5) is treated as the
  /// prefix. Returns a view without the prefix, or [data] unchanged.
  static Uint8List stripNumSignersPrefix(Uint8List data) {
    if (data.length > 1 && data[0] == 0x01 && data[1] >= 2 && data[1] <= 5) {
      return Uint8List.sublistView(data, 1);
    }
    return data;
  }

  /// Parse a BIP-32 derivation path from the beginning of [data], returning
  /// both the path string and the remaining payload bytes.
  ///
  /// Returns `null` if the path data is invalid or [data] is too short.
  static PathParseResult? parsePathWithRemainder(Uint8List data) {
    if (data.isEmpty) return null;

    final depth = data[0];
    if (depth > 10) return null; // sanity check
    final pathBytesLen = 1 + depth * 4;
    if (data.length < pathBytesLen) return null;

    final pathBytes = Uint8List.sublistView(data, 0, pathBytesLen);
    final remainder = Uint8List.sublistView(data, pathBytesLen);

    final path = parsePath(pathBytes);
    if (path == null) return null;

    return PathParseResult(path, remainder);
  }
}

/// Result of parsing a derivation path from APDU data with a remainder.
class PathParseResult {
  final String path;
  final Uint8List remainder;

  const PathParseResult(this.path, this.remainder);
}
