/// Immutable semantic signing intent — everything needed to sign a
/// payload without re-dispatching a raw wire APDU.
///
/// Created by the APDU assembler (for chunked ETH tx) or by the
/// intercept logic (for single-APDU sign commands). On approval, the
/// semantic signer uses this intent to produce a signature directly,
/// rather than feeding a raw [ApduCommand] back through the APDU
/// handler.
///
/// All [Uint8List] fields are defensive copies — modifying the
/// original source bytes after construction does not affect the
/// intent's payload.
library;

import 'dart:typed_data';

/// An immutable, self-contained description of what to sign.
///
/// Does NOT hold a raw [ApduCommand]. The approval coordinator and
/// semantic signer use this to sign the complete payload exactly once.
class SigningIntent {
  /// Chain identifier: 'ethereum', 'personal_msg', 'eip712', 'solana',
  /// 'bitcoin', 'tron', 'sui'.
  final String chain;

  /// BIP-32 derivation path string (e.g. `"m/44'/60'/0'/0/0"`).
  final String derivationPath;

  /// Pre-computed seed hex for key derivation.
  final String seedHex;

  /// Complete payload to sign:
  /// - ethereum: raw RLP bytes
  /// - personal_msg: message bytes
  /// - eip712: 64-byte combined `domainHash(32) + structHash(32)`
  /// - solana/sui: message bytes
  /// - bitcoin/tron: tx data bytes
  ///
  /// This is a defensive copy — the original bytes cannot be modified
  /// through this reference.
  final Uint8List payload;

  /// Signing address derived from seed + path (for display only).
  final String signingAddress;

  /// Parsed transaction data from Rust SDK (JSON-decoded map), if
  /// available. Keys depend on [chain].
  final Map<String, dynamic>? parsedData;

  SigningIntent({
    required this.chain,
    required this.derivationPath,
    required this.seedHex,
    required Uint8List payload,
    required this.signingAddress,
    this.parsedData,
  }) : payload = Uint8List.fromList(payload); // defensive copy
}
