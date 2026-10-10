import 'dart:typed_data';

import 'package:open_ledger_app/core/interfaces/crypto_service.dart';

import 'sample_mnemonic.dart';

/// Minimal fake [ICryptoService] for gallery use — no FFI, no Rust.
///
/// Provides just enough behaviour for the onboarding screens that need
/// a [MnemonicService] (Entropy / ImportMnemonic).
class FakeCryptoService implements ICryptoService {

  // ── Export (ADR-011) — inert: these fakes never export a real key ────

  @override
  Uint8List? publicKeyForChain(String chain, String privkeyHex) => null;

  @override
  String? encodePrivateKey(String chain, String privkeyHex) => null;

  @override
  String generateMnemonic({int strength = 128}) => sampleMnemonic;

  @override
  bool validateMnemonic(String mnemonic) => true;

  @override
  String reencodeMnemonic(String mnemonic) => mnemonic;

  @override
  String? generateMnemonicLang({int strength = 128, required int language}) =>
      null;

  @override
  bool validateMnemonicLang(String mnemonic, int language) => true;

  @override
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) => null;

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
  String? chacha20Encrypt(String plaintext, String pin, String saltHex) =>
      null;

  @override
  String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex) =>
      null;

  @override
  String? hkdfExpand32(String prkHex, String info) => null;

  @override
  String? aeadEncryptWithKey(String plaintext, String keyHex) => null;

  @override
  String? aeadDecryptWithKey(String ciphertextHex, String keyHex) => null;

  @override
  bool constantTimeEquals(String a, String b) => a == b;

  @override
  String? historyEncrypt(String plaintext, String seedHex) => null;

  @override
  String? historyDecrypt(String cipherHex, String seedHex) => null;

  @override
  String hexEncode(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  Uint8List hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
