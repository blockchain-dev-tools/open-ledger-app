/// Shared fake [ICryptoService] for tests.
///
/// Provides REAL pure-Dart hex utilities so tests exercising ApduHandler's
/// hex-dependent paths (e.g. EIP-712 sign-payload decoding) work without the
/// Rust `.so`. All FFI-backed methods return safe
/// defaults (`null` / `false` / `''`) rather than throwing, so a test that
/// accidentally reaches a signing path fails gracefully with an APDU error
/// response instead of crashing on FFI library load.
library;

import 'dart:typed_data';

import 'package:open_ledger_app/core/interfaces/crypto_service.dart';

import 'inert_export.dart';
import 'inert_key_hierarchy.dart';

class FakeCryptoService with InertKeyHierarchy, InertExport implements ICryptoService {
  const FakeCryptoService();

  // ── Real pure-Dart hex utilities ────────────────────────────────────

  @override
  String hexEncode(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  Uint8List hexToBytes(String hex) {
    if (hex.length.isOdd) throw ArgumentError('Invalid hex string (odd length)');
    return Uint8List.fromList(List.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ));
  }

  /// Real (non-FFI) comparison so tests exercising `PinBiz.verifyPin` work
  /// without the Rust .so.
  @override
  bool constantTimeEquals(String a, String b) => a == b;

  // ── FFI-backed: safe non-throwing defaults ──────────────────────────
  // Non-nullable returns use empty/false; nullable returns use null.

  @override
  String generateMnemonic({int strength = 128}) => '';

  @override
  bool validateMnemonic(String mnemonic) => false;

  @override
  String reencodeMnemonic(String mnemonic) => '';

  @override
  String? generateMnemonicLang({int strength = 128, required int language}) =>
      null;

  @override
  bool validateMnemonicLang(String mnemonic, int language) => false;

  @override
  Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) => null;

  @override
  Uint8List? deriveSecp256k1Extended(String seedHex, String path) => null;

  @override
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path) => null;

  @override
  Uint8List? signEthTransaction(String privkeyHex, String rlpHex) => null;

  @override
  Uint8List? signEthPersonalMessage(String privkeyHex, String messageHex) =>
      null;

  @override
  Uint8List? signEthEIP712(
          String privkeyHex, String domainHashHex, String structHashHex) =>
      null;

  @override
  Uint8List? signSolanaMessage(String privkeyHex, String messageHex) => null;

  @override
  String? ethAddressFromPrivateKey(String privkeyHex) => null;

  @override
  Uint8List? ethPublicKeyBytes(String privkeyHex) => null;

  @override
  Uint8List? solanaPublicKeyBytes(String privkeyHex) => null;

  @override
  String? deriveEthAddress(String seedHex, String path) => null;

  @override
  String? deriveSolAddress(String seedHex, String path) => null;

  @override
  String? deriveBtcAddress(String seedHex, String path) => null;

  @override
  String? deriveTronAddress(String seedHex, String path) => null;

  @override
  String? deriveSuiAddress(String seedHex, String path) => null;

  @override
  String? deriveNearAddress(String seedHex, String path) => null;

  @override
  String? deriveTonAddress(String seedHex, String path) => null;

  @override
  String? p2wpkhAddress(String compressedPubkeyHex) => null;

  @override
  String? tronAddressFromPubkey(String uncompressedPubkeyHex) => null;

  @override
  String? suiAddress(String ed25519PubkeyHex) => null;

  @override
  String? enigmaDeriveMnemonic(String riddle, String secret, int language) =>
      null;

  @override
  String? enigmaEntropyHex(String riddle, String secret, int language) => null;

  @override
  String? mnemonicFromEntropy(String entropyHex, int language) => null;

  @override
  String? parseSignData(String chain, String payloadHex) => null;

  @override
  String? pbkdf2Derive(String pin, String saltHex, int keyLen) => null;

  @override
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) => null;

  @override
  String? chacha20Encrypt(String plaintext, String pin, String saltHex) => null;

  @override
  String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex) =>
      null;

  @override
  String? historyEncrypt(String plaintext, String seedHex) => plaintext;

  @override
  String? historyDecrypt(String cipherHex, String seedHex) => cipherHex;
}