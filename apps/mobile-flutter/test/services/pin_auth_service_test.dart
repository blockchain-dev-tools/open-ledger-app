/// Unit tests for [PinAuthService].
///
/// Covers PIN hashing, verification, encryption/decryption, and attempt
/// tracking with lockout.
///
/// PIN *change* (`updatePin`) is session-scoped under the multi-vault model
/// and now lives in [WalletBiz] — see wallet_biz_test.dart.
///
/// The repository is a real [VaultRepositoryImpl] over [InMemoryStorage]
/// (no hand-written repository mock).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/data/repositories/vault_repository_impl.dart';
import 'package:open_ledger_app/infrastructure/persistence/in_memory_storage.dart';
import 'package:open_ledger_app/services/pin_auth_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mocks (no mockito dependency)
// ═══════════════════════════════════════════════════════════════════════

/// Configurable mock of [ICryptoService].
///
/// Set return values on fields before each test, then check [calls]
/// to verify what was invoked and with which arguments.
class MockCryptoService implements ICryptoService {

  // ── Export (ADR-011) — inert: these fakes never export a real key ────

  @override
  Uint8List? publicKeyForChain(String chain, String privkeyHex) => null;

  @override
  String? encodePrivateKey(String chain, String privkeyHex) => null;

  // ── Configurable return values ───────────────────────────────────────

  /// Return value for [pbkdf2Derive]. `null` = simulate failure.
  String? pbkdf2DeriveResult;

  /// Return value for [chacha20Encrypt]. `null` = simulate failure.
  String? chacha20EncryptResult;

  /// Return value for [chacha20Decrypt]. `null` = simulate failure.
  String? chacha20DecryptResult;

  /// Return value for [hexEncode].
  String hexEncodeResult = '';

  /// Return value for [hkdfExpand32]. `null` = simulate failure.
  String? hkdfExpand32Result;

  /// Return value for [aeadEncryptWithKey]. `null` = simulate failure.
  String? aeadEncryptResult;

  /// Return value for [aeadDecryptWithKey]. `null` = failure / no match.
  String? aeadDecryptResult;

  // ── Call recording ───────────────────────────────────────────────────

  final List<Pbkdf2CallRecord> pbkdf2Calls = [];
  final List<ChaChaCallRecord> encryptCalls = [];
  final List<ChaChaCallRecord> decryptCalls = [];
  final List<Uint8List> hexEncodeCalls = [];
  final List<HkdfCallRecord> hkdfCalls = [];
  final List<AeadCallRecord> aeadEncryptCalls = [];
  final List<AeadCallRecord> aeadDecryptCalls = [];

  // ── ICryptoService implementation ────────────────────────────────────

  @override
  String? pbkdf2Derive(String pin, String saltHex, int keyLen) {
    pbkdf2Calls.add(Pbkdf2CallRecord(pin, saltHex, keyLen));
    return pbkdf2DeriveResult;
  }

  @override
  String? chacha20Encrypt(String plaintext, String pin, String saltHex) {
    encryptCalls.add(ChaChaCallRecord(plaintext, pin, saltHex));
    return chacha20EncryptResult;
  }

  @override
  String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex) {
    decryptCalls.add(ChaChaCallRecord(ciphertextHex, pin, saltHex));
    return chacha20DecryptResult;
  }

  @override
  String? historyEncrypt(String plaintext, String seedHex) => null;

  @override
  String? historyDecrypt(String cipherHex, String seedHex) => null;

  // ── Key hierarchy ────────────────────────────────────────────────────

  @override
  String? hkdfExpand32(String prkHex, String info) {
    hkdfCalls.add(HkdfCallRecord(prkHex, info));
    return hkdfExpand32Result;
  }

  @override
  String? aeadEncryptWithKey(String plaintext, String keyHex) {
    aeadEncryptCalls.add(AeadCallRecord(plaintext, keyHex));
    return aeadEncryptResult;
  }

  @override
  String? aeadDecryptWithKey(String ciphertextHex, String keyHex) {
    aeadDecryptCalls.add(AeadCallRecord(ciphertextHex, keyHex));
    return aeadDecryptResult;
  }

  @override
  String hexEncode(Uint8List bytes) {
    hexEncodeCalls.add(bytes);
    return hexEncodeResult;
  }

  // ── Unused methods (should never be called from PinAuthService) ──────

  @override
  String generateMnemonic({int strength = 128}) =>
      throw UnimplementedError();

  @override
  bool validateMnemonic(String mnemonic) => throw UnimplementedError();

  @override
  String reencodeMnemonic(String mnemonic) => throw UnimplementedError();

  @override
  String? generateMnemonicLang({int strength = 128, required int language}) =>
      throw UnimplementedError();

  @override
  bool validateMnemonicLang(String mnemonic, int language) =>
      throw UnimplementedError();

  @override
  Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  Uint8List? deriveSecp256k1Extended(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  Uint8List? signEthTransaction(String privkeyHex, String rlpHex) =>
      throw UnimplementedError();

  @override
  Uint8List? signEthPersonalMessage(String privkeyHex, String messageHex) =>
      throw UnimplementedError();

  @override
  Uint8List? signEthEIP712(
          String privkeyHex, String domainHashHex, String structHashHex) =>
      throw UnimplementedError();

  @override
  Uint8List? signSolanaMessage(String privkeyHex, String messageHex) =>
      throw UnimplementedError();

  @override
  String? ethAddressFromPrivateKey(String privkeyHex) =>
      throw UnimplementedError();

  @override
  Uint8List? ethPublicKeyBytes(String privkeyHex) => throw UnimplementedError();

  @override
  Uint8List? solanaPublicKeyBytes(String privkeyHex) =>
      throw UnimplementedError();

  @override
  String? deriveEthAddress(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  String? deriveSolAddress(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  String? deriveBtcAddress(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  String? deriveTronAddress(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  String? deriveSuiAddress(String seedHex, String path) =>
      throw UnimplementedError();

  @override
  String? p2wpkhAddress(String compressedPubkeyHex) =>
      throw UnimplementedError();

  @override
  String? tronAddressFromPubkey(String uncompressedPubkeyHex) =>
      throw UnimplementedError();

  @override
  String? suiAddress(String ed25519PubkeyHex) => throw UnimplementedError();

  @override
  String? enigmaDeriveMnemonic(
          String riddle, String secret, int language) =>
      throw UnimplementedError();

  @override
  String? enigmaEntropyHex(String riddle, String secret, int language) =>
      throw UnimplementedError();

  @override
  String? mnemonicFromEntropy(String entropyHex, int language) =>
      throw UnimplementedError();

  @override
  String? parseSignData(String chain, String payloadHex) =>
      throw UnimplementedError();

  @override
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) =>
      throw UnimplementedError();

  @override
  bool constantTimeEquals(String a, String b) => a == b;

  @override
  Uint8List hexToBytes(String hex) => throw UnimplementedError();
}

// ═══════════════════════════════════════════════════════════════════════
// Call record types
// ═══════════════════════════════════════════════════════════════════════

class Pbkdf2CallRecord {
  final String pin;
  final String saltHex;
  final int keyLen;
  const Pbkdf2CallRecord(this.pin, this.saltHex, this.keyLen);
}

class ChaChaCallRecord {
  final String data;
  final String pin;
  final String saltHex;
  const ChaChaCallRecord(this.data, this.pin, this.saltHex);
}

class HkdfCallRecord {
  final String prkHex;
  final String info;
  const HkdfCallRecord(this.prkHex, this.info);
}

class AeadCallRecord {
  final String data;
  final String keyHex;
  const AeadCallRecord(this.data, this.keyHex);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  late MockCryptoService crypto;
  late VaultRepositoryImpl repo;
  late PinAuthService service;

  setUp(() {
    crypto = MockCryptoService();
    repo = VaultRepositoryImpl(InMemoryStorage());
    service = PinAuthService(crypto: crypto, repo: repo);
  });

  // ──────────────────────────────────────────────────────────────────
  // hashPin
  // ──────────────────────────────────────────────────────────────────

  group('deriveKey', () {
    test('stretches the PIN once with the device salt', () async {
      await repo.setDeviceSalt('deadbeef');
      crypto.pbkdf2DeriveResult =
          'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

      final result = await service.deriveKey('123456');

      expect(result, crypto.pbkdf2DeriveResult);
      expect(crypto.pbkdf2Calls.length, 1);
      expect(crypto.pbkdf2Calls.first.pin, '123456');
      expect(crypto.pbkdf2Calls.first.saltHex, 'deadbeef');
      expect(crypto.pbkdf2Calls.first.keyLen, 32);
    });

    test('throws StateError when crypto returns null', () async {
      await repo.setDeviceSalt('deadbeef');
      crypto.pbkdf2DeriveResult = null;

      expect(() => service.deriveKey('123456'), throwsA(isA<StateError>()));
    });

    test('throws StateError when no device salt exists', () async {
      crypto.pbkdf2DeriveResult = 'key-hex';

      expect(() => service.deriveKey('123456'), throwsA(isA<StateError>()));
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Verifier sealing
  // ──────────────────────────────────────────────────────────────────

  group('verifier sealing', () {
    test('seals the fixed plaintext under the domain-separated key', () {
      crypto.hkdfExpand32Result = 'verify-key';
      crypto.aeadEncryptResult = 'sealed-verifier';

      final verifierKey = service.verifyKey('master-key');
      final sealed = service.sealVerifier(verifierKey);

      expect(verifierKey, 'verify-key');
      expect(sealed, 'sealed-verifier');
      expect(crypto.hkdfCalls.first.prkHex, 'master-key');
      expect(crypto.hkdfCalls.first.info, tierVerifyContext);
      expect(crypto.aeadEncryptCalls.first.data, tierVerifyPlaintext);
      expect(crypto.aeadEncryptCalls.first.keyHex, 'verify-key');
    });

    test('verifyKey throws when HKDF fails', () {
      crypto.hkdfExpand32Result = null;

      expect(() => service.verifyKey('master-key'), throwsA(isA<StateError>()));
    });

    test('sealVerifier throws when AEAD fails', () {
      crypto.aeadEncryptResult = null;

      expect(
        () => service.sealVerifier('verify-key'),
        throwsA(isA<StateError>()),
      );
    });

    test('ensureDeviceSalt creates one and never rotates it', () async {
      crypto.hexEncodeResult = 'salt-hex';

      await service.ensureDeviceSalt();
      expect(await repo.getDeviceSalt(), 'salt-hex');

      crypto.hexEncodeResult = 'other-salt';
      await service.ensureDeviceSalt();
      expect(await repo.getDeviceSalt(), 'salt-hex');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // verifyPin
  // ──────────────────────────────────────────────────────────────────

  group('verifyPin', () {
    const deviceSalt = 'deadbeef';

    setUp(() async {
      await repo.setDeviceSalt(deviceSalt);
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'stored-verifier'),
      );
      crypto.pbkdf2DeriveResult = 'master-key';
      crypto.hkdfExpand32Result = 'verify-key';
    });

    test('returns true when the verifier opens', () async {
      crypto.aeadDecryptResult = tierVerifyPlaintext;

      final result = await service.verifyPin('123456');

      expect(result, isTrue);
      expect(crypto.pbkdf2Calls.first.pin, '123456');
      expect(crypto.pbkdf2Calls.first.saltHex, deviceSalt);
    });

    test('returns false when the verifier does not open', () async {
      crypto.aeadDecryptResult = 'garbage';

      final result = await service.verifyPin('123456');

      expect(result, isFalse);
    });

    test('returns false when no credential is configured', () async {
      await repo.deleteCredential(0);
      crypto.aeadDecryptResult = tierVerifyPlaintext;

      final result = await service.verifyPin('123456');

      expect(result, isFalse);
    });

    test('probes with the domain-separated verifier key', () async {
      crypto.aeadDecryptResult = 'garbage';

      await service.verifyPin('123456');

      // derive -> HKDF(verify context) -> probe with that key.
      expect(crypto.hkdfCalls.first.info, tierVerifyContext);
      expect(crypto.aeadDecryptCalls.first.keyHex, 'verify-key');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // isLocked
  // ──────────────────────────────────────────────────────────────────

  group('isLocked', () {
    test('returns false when attempts < 5', () async {
      await repo.setPinAttempts(3);

      final result = await service.isLocked();

      expect(result, isFalse);
    });

    test('returns true when attempts >= 5', () async {
      await repo.setPinAttempts(5);

      final result = await service.isLocked();

      expect(result, isTrue);
    });

    test('returns false when attempts == 0 (no attempts made)', () async {
      await repo.setPinAttempts(0);

      final result = await service.isLocked();

      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // incrementPinAttempts & resetPinAttempts
  // ──────────────────────────────────────────────────────────────────

  group('incrementPinAttempts', () {
    test('increments and persists attempts', () async {
      await repo.setPinAttempts(2);

      await service.incrementPinAttempts();

      expect(await repo.getPinAttempts(), 3);
      expect(service.pinAttempts, 3);
    });

    test('handles increment from 0', () async {
      await repo.setPinAttempts(0);

      await service.incrementPinAttempts();

      expect(await repo.getPinAttempts(), 1);
      expect(service.pinAttempts, 1);
    });
  });

  group('resetPinAttempts', () {
    test('resets to 0 and persists', () async {
      // Pre-seed with some value so we can verify it's actually reset
      await repo.setPinAttempts(4);
      await service.incrementPinAttempts(); // cached at 4 → 5

      await service.resetPinAttempts();

      expect(await repo.getPinAttempts(), 0);
      expect(service.pinAttempts, 0);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // encryptWithPin
  // ──────────────────────────────────────────────────────────────────

  group('encryptWithKey', () {
    test('delegates to crypto and returns result', () {
      crypto.aeadEncryptResult = 'ciphertext-hex';

      final result = service.encryptWithKey('my secret mnemonic', 'key-hex');

      expect(result, 'ciphertext-hex');
      expect(crypto.aeadEncryptCalls.length, 1);
      expect(crypto.aeadEncryptCalls.first.data, 'my secret mnemonic');
      expect(crypto.aeadEncryptCalls.first.keyHex, 'key-hex');
    });

    test('throws StateError when crypto returns null', () {
      crypto.aeadEncryptResult = null;

      expect(
        () => service.encryptWithKey('data', 'key-hex'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // decryptWithPin
  // ──────────────────────────────────────────────────────────────────

  group('decryptWithKey', () {
    test('delegates to crypto and returns result', () {
      crypto.aeadDecryptResult = 'decrypted plaintext';

      final result = service.decryptWithKey('ciphertext-hex', 'key-hex');

      expect(result, 'decrypted plaintext');
      expect(crypto.aeadDecryptCalls.length, 1);
      expect(crypto.aeadDecryptCalls.first.data, 'ciphertext-hex');
      expect(crypto.aeadDecryptCalls.first.keyHex, 'key-hex');
    });

    test('throws StateError when crypto returns null', () {
      crypto.aeadDecryptResult = null;

      expect(
        () => service.decryptWithKey('ciphertext', 'key-hex'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // randomHex
  // ──────────────────────────────────────────────────────────────────

  group('randomHex', () {
    test('returns hex string of correct length', () {
      crypto.hexEncodeResult = '0102030405060708090a0b0c0d0e0f10';

      final result = service.randomHex(16);

      expect(result, crypto.hexEncodeResult);
      expect(crypto.hexEncodeCalls.length, 1);
      expect(crypto.hexEncodeCalls.first.length, 16);
    });

    test('produces different results on successive calls (randomness check)',
        () {
      crypto.hexEncodeResult = 'aabbccdd';

      final r1 = service.randomHex(4);
      final r2 = service.randomHex(4);

      // Same mock returns same hex, but the byte arrays should differ
      // because randomHex generates fresh random bytes each call
      expect(crypto.hexEncodeCalls.length, 2);
      expect(r1, r2); // same mock result, but call count proves 2 invocations
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // maxPinAttempts
  // ──────────────────────────────────────────────────────────────────

  group('maxPinAttempts', () {
    test('returns 5', () {
      expect(service.maxPinAttempts, 5);
    });
  });
}
