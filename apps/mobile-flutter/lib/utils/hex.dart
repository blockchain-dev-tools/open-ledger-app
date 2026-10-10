import 'dart:typed_data';

/// Unified hex encoding/decoding utilities.
///
/// This is the single source of truth for hex operations in the project.
/// All other hex implementations (CryptoBridge.hexEncode, airgap Hex class)
/// should eventually delegate here.
class Hex {
  /// Encode bytes to lowercase hex string.
  static String encode(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Decode hex string to bytes.
  static Uint8List decode(String hex) {
    if (hex.length % 2 != 0) {
      throw ArgumentError('Invalid hex string (odd length): $hex');
    }
    return Uint8List.fromList(List.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ));
  }
}
