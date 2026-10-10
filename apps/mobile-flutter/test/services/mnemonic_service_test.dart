/// Unit tests for [MnemonicService].
///
/// Covers BIP-39 generation/validation delegation, seed derivation,
/// fingerprint determinism, Enigma generation, and error cases.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import '../support/inert_export.dart';
import '../support/inert_key_hierarchy.dart';
import 'package:open_ledger_app/core/interfaces/mnemonic_service.dart';
import 'package:open_ledger_app/services/mnemonic_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock ICryptoService
// ─────────────────────────────────────────────────────────────────────────────

/// Hand-written mock implementing [ICryptoService].
///
/// Mnemonic-related methods are configurable via constructor parameters.
/// All other methods throw [UnimplementedError] — a test reaching them
/// indicates an unexpected code path.
class _MockCryptoService with InertKeyHierarchy, InertExport implements ICryptoService {
  final String _generateResult =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  final bool _validateResult;
  final String? _seedResult;
  final String _enigmaResult =
      'click fuel subject claw shoulder region assume scout east nice prize meat planet delay galaxy code satisfy identify leopard fork market isolate jungle purpose';
  final List<String> _callLog;

  _MockCryptoService({
    this._validateResult = true,
    this._seedResult = '5eb00bbddcf069084889a8ab9155568165f5c453ccf85a70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4',
    List<String>? callLog,
  }) : _callLog = callLog ?? [];

  // ── Mnemonic (used by MnemonicService) ─────────────────────────────────

  @override
  String generateMnemonic({int strength = 128}) {
    _callLog.add('generateMnemonic(strength:$strength)');
    return _generateResult;
  }

  @override
  bool validateMnemonic(String mnemonic) {
    _callLog.add('validateMnemonic($mnemonic)');
    return _validateResult;
  }

  @override
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) {
    _callLog.add('mnemonicToSeed(mnemonic, passphrase:$passphrase)');
    return _seedResult;
  }

  // ── Not used by MnemonicService ────────────────────────────────────────

  @override
  String reencodeMnemonic(String mnemonic) => _fail('reencodeMnemonic');

  @override
  String? generateMnemonicLang({int strength = 128, required int language}) =>
      _fail('generateMnemonicLang');

  @override
  bool validateMnemonicLang(String mnemonic, int language) =>
      _fail('validateMnemonicLang');

  @override
  Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) =>
      _fail('deriveSecp256k1PrivateKey');

  @override
  Uint8List? deriveSecp256k1Extended(String seedHex, String path) =>
      _fail('deriveSecp256k1Extended');

  @override
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path) =>
      _fail('deriveEd25519PrivateKey');

  @override
  Uint8List? signEthTransaction(String privkeyHex, String rlpHex) =>
      _fail('signEthTransaction');

  @override
  Uint8List? signEthPersonalMessage(String privkeyHex, String messageHex) =>
      _fail('signEthPersonalMessage');

  @override
  Uint8List? signEthEIP712(
          String privkeyHex, String domainHashHex, String structHashHex) =>
      _fail('signEthEIP712');

  @override
  Uint8List? signSolanaMessage(String privkeyHex, String messageHex) =>
      _fail('signSolanaMessage');

  @override
  String? ethAddressFromPrivateKey(String privkeyHex) =>
      _fail('ethAddressFromPrivateKey');

  @override
  Uint8List? ethPublicKeyBytes(String privkeyHex) =>
      _fail('ethPublicKeyBytes');

  @override
  Uint8List? solanaPublicKeyBytes(String privkeyHex) =>
      _fail('solanaPublicKeyBytes');

  @override
  String? deriveEthAddress(String seedHex, String path) =>
      _fail('deriveEthAddress');

  @override
  String? deriveSolAddress(String seedHex, String path) =>
      _fail('deriveSolAddress');

  @override
  String? deriveBtcAddress(String seedHex, String path) =>
      _fail('deriveBtcAddress');

  @override
  String? deriveTronAddress(String seedHex, String path) =>
      _fail('deriveTronAddress');

  @override
  String? deriveSuiAddress(String seedHex, String path) =>
      _fail('deriveSuiAddress');

  @override
  String? p2wpkhAddress(String compressedPubkeyHex) =>
      _fail('p2wpkhAddress');

  @override
  String? tronAddressFromPubkey(String uncompressedPubkeyHex) =>
      _fail('tronAddressFromPubkey');

  @override
  String? suiAddress(String ed25519PubkeyHex) => _fail('suiAddress');

  @override
  String? enigmaDeriveMnemonic(
      String riddle, String secret, int language) {
    _callLog.add('enigmaDeriveMnemonic(riddle:$riddle, secret:$secret, lang:$language)');
    return _enigmaResult;
  }

  @override
  String? enigmaEntropyHex(String riddle, String secret, int language) =>
      _fail('enigmaEntropyHex');

  @override
  String? mnemonicFromEntropy(String entropyHex, int language) =>
      _fail('mnemonicFromEntropy');

  @override
  String? parseSignData(String chain, String payloadHex) =>
      _fail('parseSignData');

  @override
  String? pbkdf2Derive(String pin, String saltHex, int keyLen) =>
      _fail('pbkdf2Derive');

  @override
  String? chacha20Encrypt(String plaintext, String pin, String saltHex) =>
      _fail('chacha20Encrypt');

  @override
  String? chacha20Decrypt(
          String ciphertextHex, String pin, String saltHex) =>
      _fail('chacha20Decrypt');

  @override
  String? historyEncrypt(String plaintext, String seedHex) =>
      _fail('historyEncrypt');

  @override
  String? historyDecrypt(String cipherHex, String seedHex) =>
      _fail('historyDecrypt');

  @override
  String hexEncode(Uint8List bytes) => _fail('hexEncode');

  @override
  bool constantTimeEquals(String a, String b) => a == b;

  @override
  Uint8List hexToBytes(String hex) => _fail('hexToBytes');

  Never _fail(String method) =>
      throw UnimplementedError('MockCryptoService.$method should not be called by MnemonicService');
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late IMnemonicService service;
  late _MockCryptoService mockCrypto;
  late List<String> callLog;

  setUp(() {
    callLog = [];
    mockCrypto = _MockCryptoService(callLog: callLog);
    service = MnemonicService(crypto: mockCrypto);
  });

  // ═══════════════════════════════════════════════════════════════════════
  // generateMnemonic
  // ═══════════════════════════════════════════════════════════════════════

  test('generateMnemonic delegates to crypto and returns result', () {
    const expected =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

    final result = service.generateMnemonic();

    expect(result, expected);
    expect(callLog, contains('generateMnemonic(strength:128)'));
  });

  test('generateMnemonic passes strength parameter to crypto', () {
    service.generateMnemonic(strength: 256);

    expect(callLog, contains('generateMnemonic(strength:256)'));
  });

  // ═══════════════════════════════════════════════════════════════════════
  // validateMnemonic
  // ═══════════════════════════════════════════════════════════════════════

  test('validateMnemonic returns true for valid mnemonic', () {
    final result = service.validateMnemonic(
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );

    expect(result, isTrue);
  });

  test('validateMnemonic returns false for invalid mnemonic', () {
    mockCrypto = _MockCryptoService(validateResult: false, callLog: callLog);
    service = MnemonicService(crypto: mockCrypto);

    final result = service.validateMnemonic('not a valid mnemonic at all');

    expect(result, isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  // mnemonicToSeedHex
  // ═══════════════════════════════════════════════════════════════════════

  test('mnemonicToSeedHex returns seed hex string', () {
    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

    final seed = service.mnemonicToSeedHex(mnemonic, '');

    expect(seed, isA<String>());
    expect(seed.length, 128); // 64 bytes = 128 hex chars
    expect(seed, equals(mockCrypto._seedResult));
  });

  test('mnemonicToSeedHex throws StateError when crypto returns null', () {
    mockCrypto = _MockCryptoService(seedResult: null, callLog: callLog);
    service = MnemonicService(crypto: mockCrypto);

    expect(
      () => service.mnemonicToSeedHex('invalid mnemonic', ''),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('BIP-39 seed derivation failed'),
      )),
    );
  });

  test('mnemonicToSeedHex passes passphrase through to crypto', () {
    const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    const passphrase = 'my-secret-passphrase';

    service.mnemonicToSeedHex(mnemonic, passphrase);

    expect(
      callLog,
      contains('mnemonicToSeed(mnemonic, passphrase:$passphrase)'),
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // fingerprintMnemonic — pure Dart FNV-1a, no mock needed
  // ═══════════════════════════════════════════════════════════════════════

  test('fingerprintMnemonic returns 8-char hex string', () {
    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

    final fingerprint = service.fingerprintMnemonic(mnemonic);

    expect(fingerprint, isA<String>());
    expect(fingerprint.length, 8);
    expect(fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('fingerprintMnemonic is deterministic (same input → same output)', () {
    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

    final fp1 = service.fingerprintMnemonic(mnemonic);
    final fp2 = service.fingerprintMnemonic(mnemonic);

    expect(fp1, equals(fp2));
  });

  test('fingerprintMnemonic different inputs produce different outputs', () {
    const mnemonic1 =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    const mnemonic2 =
        'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';

    final fp1 = service.fingerprintMnemonic(mnemonic1);
    final fp2 = service.fingerprintMnemonic(mnemonic2);

    expect(fp1, isNot(equals(fp2)));
  });

  // ═══════════════════════════════════════════════════════════════════════
  // generateEnigmaMnemonic — delegates to ICryptoService.enigmaDeriveMnemonic
  // Algorithm correctness is tested in `cd rust && cargo test`.
  // ═══════════════════════════════════════════════════════════════════════

  test('generateEnigmaMnemonic returns 24 words for default language', () {
    final words = service.generateEnigmaMnemonic('my-riddle', 'my-secret');

    expect(words, isA<List<String>>());
    expect(words.length, 24);
    for (final word in words) {
      expect(word, isNotEmpty);
    }
  });

  test('generateEnigmaMnemonic delegates with correct parameters', () {
    callLog.clear();
    final words = service.generateEnigmaMnemonic('hint-riddle', 'hint-secret');

    expect(words.length, 24);
    expect(callLog, contains(
      'enigmaDeriveMnemonic(riddle:hint-riddle, secret:hint-secret, lang:0)',
    ));
  });

  test('generateEnigmaMnemonic passes language index through', () {
    callLog.clear();
    service.generateEnigmaMnemonic('r', 's', language: 1);

    expect(callLog, contains(
      'enigmaDeriveMnemonic(riddle:r, secret:s, lang:1)',
    ));
  });

}
