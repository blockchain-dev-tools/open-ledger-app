/// Unit tests for [PinBiz].
///
/// Covers verifyPin / matchCredential (verifier probing, depth selection,
/// constant work), isLocked, incrementPinAttempts, resetPinAttempts, getters.
///
/// PIN *change* (`updatePin`) is session-scoped under the multi-vault model
/// and lives in [WalletBiz] — see wallet_biz_test.dart.
///
/// The repository is a real [VaultRepositoryImpl] over [InMemoryStorage]
/// (no hand-written repository mock).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/pin_biz.dart';
import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/data/repositories/vault_repository_impl.dart';
import 'package:open_ledger_app/infrastructure/persistence/in_memory_storage.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mocks
// ═══════════════════════════════════════════════════════════════════════

/// Deterministic stand-in for the key hierarchy.
///
/// No Rust and no real cryptography, but internally **consistent**
/// (derive → HKDF → seal → open round-trips), so the logic under test —
/// slot probing, depth selection, attempt counting — is exercised for real.
class _MockCryptoService implements ICryptoService {

  // ── Export (ADR-011) — inert: these fakes never export a real key ────

  @override
  Uint8List? publicKeyForChain(String chain, String privkeyHex) => null;

  @override
  String? encodePrivateKey(String chain, String privkeyHex) => null;

  /// Override the master key some PIN derives (default `k:<pin>`).
  final Map<String, String> masterKeys = {};

  /// Simulate an FFI failure in [deriveMasterKey].
  bool pbkdf2Fails = false;

  final List<_Pbkdf2Call> pbkdf2Calls = [];
  final List<_MasterKeyCall> masterKeyCalls = [];
  final List<_SealAttempt> sealAttempts = [];

  String _key(String pin) => masterKeys[pin] ?? 'k:$pin';

  /// Key for a KDF [version]. Argon2id is prefixed so the two versions can never
  /// be confused — the real Rust KDF guarantees the same property.
  String _keyFor(String pin, int version) =>
      version == kdfVersionPbkdf2Legacy ? _key(pin) : 'argon2:${_key(pin)}';

  @override
  String? pbkdf2Derive(String pin, String saltHex, int keyLen) {
    pbkdf2Calls.add(_Pbkdf2Call(pin, saltHex, keyLen));
    return pbkdf2Fails ? null : _key(pin);
  }

  @override
  String? deriveMasterKey(String pin, String saltHex, int version) {
    masterKeyCalls.add(_MasterKeyCall(pin, saltHex, version));
    return pbkdf2Fails ? null : _keyFor(pin, version);
  }

  @override
  String? hkdfExpand32(String prkHex, String info) => 'h:$info:$prkHex';

  @override
  String? aeadEncryptWithKey(String plaintext, String keyHex) =>
      'ct:$keyHex:$plaintext';

  @override
  String? aeadDecryptWithKey(String ciphertextHex, String keyHex) {
    sealAttempts.add(_SealAttempt(ciphertextHex, keyHex));
    final prefix = 'ct:$keyHex:';
    return ciphertextHex.startsWith(prefix)
        ? ciphertextHex.substring(prefix.length)
        : null;
  }

  /// The credential value a tier unlocked by [pin] would store at [version].
  String verifierFor(String pin, [int version = kdfVersionPbkdf2Legacy]) =>
      aeadEncryptWithKey(
        tierVerifyPlaintext,
        hkdfExpand32(_keyFor(pin, version), tierVerifyContext)!,
      )!;

  @override
  String? chacha20Encrypt(String plaintext, String pin, String saltHex) =>
      throw UnimplementedError();

  @override
  String? chacha20Decrypt(String ciphertextHex, String pin, String saltHex) =>
      throw UnimplementedError();

  @override
  String? historyEncrypt(String plaintext, String seedHex) => null;

  @override
  String? historyDecrypt(String cipherHex, String seedHex) => null;

  @override
  String hexEncode(Uint8List bytes) => 'hex';

  // ── Unused ─────────────────────────────────────────────────────────

  @override String generateMnemonic({int strength = 128}) => throw UnimplementedError();
  @override bool validateMnemonic(String m) => throw UnimplementedError();
  @override String reencodeMnemonic(String m) => throw UnimplementedError();
  @override String? generateMnemonicLang({int strength = 128, required int language}) => throw UnimplementedError();
  @override bool validateMnemonicLang(String m, int l) => throw UnimplementedError();
  @override Uint8List? deriveSecp256k1PrivateKey(String s, String p) => throw UnimplementedError();
  @override Uint8List? deriveSecp256k1Extended(String s, String p) => throw UnimplementedError();
  @override Uint8List? deriveEd25519PrivateKey(String s, String p) => throw UnimplementedError();
  @override Uint8List? signEthTransaction(String k, String r) => throw UnimplementedError();
  @override Uint8List? signEthPersonalMessage(String k, String m) => throw UnimplementedError();
  @override Uint8List? signEthEIP712(String k, String d, String s) => throw UnimplementedError();
  @override Uint8List? signSolanaMessage(String k, String m) => throw UnimplementedError();
  @override String? ethAddressFromPrivateKey(String k) => throw UnimplementedError();
  @override Uint8List? ethPublicKeyBytes(String k) => throw UnimplementedError();
  @override Uint8List? solanaPublicKeyBytes(String k) => throw UnimplementedError();
  @override String? deriveEthAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveSolAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveBtcAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveTronAddress(String s, String p) => throw UnimplementedError();
  @override String? deriveSuiAddress(String s, String p) => throw UnimplementedError();
  @override String? p2wpkhAddress(String k) => throw UnimplementedError();
  @override String? tronAddressFromPubkey(String k) => throw UnimplementedError();
  @override String? suiAddress(String k) => throw UnimplementedError();
  @override String? enigmaDeriveMnemonic(String r, String s, int l) => throw UnimplementedError();
  @override String? enigmaEntropyHex(String r, String s, int l) => throw UnimplementedError();
  @override String? mnemonicFromEntropy(String e, int l) => throw UnimplementedError();
  @override String? parseSignData(String c, String p) => throw UnimplementedError();
  @override String? mnemonicToSeed(String m, {String passphrase = ''}) => throw UnimplementedError();
  @override Uint8List hexToBytes(String h) => throw UnimplementedError();
  @override bool constantTimeEquals(String a, String b) => a == b;
}

// ═══════════════════════════════════════════════════════════════════════
// Call record types
// ═══════════════════════════════════════════════════════════════════════

class _Pbkdf2Call {
  final String pin;
  final String saltHex;
  final int keyLen;
  const _Pbkdf2Call(this.pin, this.saltHex, this.keyLen);
}

class _MasterKeyCall {
  final String pin;
  final String saltHex;
  final int version;
  const _MasterKeyCall(this.pin, this.saltHex, this.version);
}

class _SealAttempt {
  final String ciphertextHex;
  final String keyHex;
  const _SealAttempt(this.ciphertextHex, this.keyHex);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  const deviceSalt = 'device-salt';

  late _MockCryptoService crypto;
  late VaultRepositoryImpl repo;
  late PinBiz pinBiz;

  setUp(() async {
    crypto = _MockCryptoService();
    repo = VaultRepositoryImpl(InMemoryStorage());
    await repo.setDeviceSalt(deviceSalt);
    pinBiz = PinBiz(crypto: crypto, repo: repo);
  });

  // ──────────────────────────────────────────────────────────────────
  // pinAttempts / maxPinAttempts getters
  // ──────────────────────────────────────────────────────────────────

  group('pinAttempts', () {
    test('returns 0 before loading (sentinel not loaded)', () {
      expect(pinBiz.pinAttempts, 0);
    });

    test('returns loaded value after isLocked triggers load', () async {
      await repo.setPinAttempts(3);
      await pinBiz.isLocked();
      expect(pinBiz.pinAttempts, 3);
    });
  });

  group('maxPinAttempts', () {
    test('returns 5', () {
      expect(PinBiz.maxPinAttempts, 5);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // isLocked
  // ──────────────────────────────────────────────────────────────────

  group('isLocked', () {
    test('returns false when attempts < 5', () async {
      await repo.setPinAttempts(0);
      expect(await pinBiz.isLocked(), isFalse);
    });

    test('returns false when attempts == 3', () async {
      await repo.setPinAttempts(3);
      expect(await pinBiz.isLocked(), isFalse);
    });

    test('returns true when attempts == 5', () async {
      await repo.setPinAttempts(5);
      expect(await pinBiz.isLocked(), isTrue);
    });

    test('returns true when attempts > 5', () async {
      await repo.setPinAttempts(10);
      expect(await pinBiz.isLocked(), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // incrementPinAttempts
  // ──────────────────────────────────────────────────────────────────

  group('incrementPinAttempts', () {
    test('increments and persists attempts', () async {
      await repo.setPinAttempts(2);
      await pinBiz.incrementPinAttempts();
      expect(pinBiz.pinAttempts, 3);
      expect(await repo.getPinAttempts(), 3);
    });

    test('handles increment from 0', () async {
      await repo.setPinAttempts(0);
      await pinBiz.incrementPinAttempts();
      expect(pinBiz.pinAttempts, 1);
      expect(await repo.getPinAttempts(), 1);
    });

    test('increment from 4 → 5 (reaches lockout threshold)', () async {
      await repo.setPinAttempts(4);
      await pinBiz.incrementPinAttempts();
      expect(pinBiz.pinAttempts, 5);
      expect(await pinBiz.isLocked(), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // resetPinAttempts
  // ──────────────────────────────────────────────────────────────────

  group('resetPinAttempts', () {
    test('resets to 0 and persists', () async {
      await repo.setPinAttempts(4);
      await pinBiz.isLocked(); // trigger load
      await pinBiz.resetPinAttempts();
      expect(pinBiz.pinAttempts, 0);
      expect(await repo.getPinAttempts(), 0);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // verifyPin
  // ──────────────────────────────────────────────────────────────────

  group('verifyPin', () {
    setUp(() async {
      await repo.setCredential(
        WalletCredential(depth: 0, verifier: crypto.verifierFor('123456')),
      );
    });

    test('returns true when the verifier opens, deriving the key once',
        () async {
      final result = await pinBiz.verifyPin('123456');

      expect(result, isTrue);
      // One derivation for the whole unlock — the tier is not part of it.
      expect(crypto.masterKeyCalls.length, 1);
      expect(crypto.masterKeyCalls.first.pin, '123456');
      expect(crypto.masterKeyCalls.first.saltHex, deviceSalt);
      // A legacy-only device derives with the legacy version, nothing else.
      expect(crypto.masterKeyCalls.first.version, kdfVersionPbkdf2Legacy);
      // Successful verify resets attempts.
      expect(pinBiz.pinAttempts, 0);
    });

    test('derives once no matter how many tiers are configured', () async {
      await repo.setCredential(
        WalletCredential(depth: 1, verifier: crypto.verifierFor('654321')),
      );
      await repo.setCredential(
        WalletCredential(depth: 2, verifier: crypto.verifierFor('777777')),
      );

      await pinBiz.verifyPin('123456');

      expect(crypto.masterKeyCalls.length, 1);
    });

    test('returns false when no verifier opens', () async {
      final result = await pinBiz.verifyPin('999999');

      expect(result, isFalse);
    });

    test('auto-increments pinAttempts on failure', () async {
      await repo.setPinAttempts(0);

      await pinBiz.verifyPin('999999');

      expect(pinBiz.pinAttempts, 1);
      expect(await repo.getPinAttempts(), 1);
    });

    test('auto-resets pinAttempts on success after failures', () async {
      await repo.setPinAttempts(3);
      await pinBiz.isLocked();
      expect(pinBiz.pinAttempts, 3);

      await pinBiz.verifyPin('123456');

      expect(pinBiz.pinAttempts, 0);
    });

    test('returns false when no credential is configured', () async {
      await repo.deleteCredential(0);
      final result = await pinBiz.verifyPin('123456');
      expect(result, isFalse);
    });

    test('matches a credential stored at a stand-in tier', () async {
      await repo.deleteCredential(0);
      await repo.setCredential(
        WalletCredential(depth: 1, verifier: crypto.verifierFor('123456')),
      );

      // Which tier owns a PIN is emergent: the same derivation opens it.
      expect(await pinBiz.verifyPin('123456'), isTrue);
      expect(await pinBiz.matchCredential('123456'), 1);
    });

    test('returns false when no credentials are configured at all', () async {
      await repo.deleteCredential(0);
      await repo.deleteCredential(1);
      final result = await pinBiz.verifyPin('123456');
      expect(result, isFalse);
    });

    test('multiple failures increment attempts cumulatively', () async {
      await repo.setPinAttempts(0);

      await pinBiz.verifyPin('wrong1');
      expect(pinBiz.pinAttempts, 1);

      await pinBiz.verifyPin('wrong2');
      expect(pinBiz.pinAttempts, 2);

      await pinBiz.verifyPin('wrong3');
      expect(pinBiz.pinAttempts, 3);
    });

    test('throws when the device salt is missing', () async {
      final bare = VaultRepositoryImpl(InMemoryStorage());
      final bareBiz = PinBiz(crypto: crypto, repo: bare);

      expect(() => bareBiz.verifyPin('123456'), throwsA(isA<StateError>()));
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // matchCredential — depth selection + constant work + key hand-off
  // ──────────────────────────────────────────────────────────────────

  group('matchCredential', () {
    test('probes every slot once for a single PBKDF2', () async {
      await repo.setCredential(
        WalletCredential(depth: 0, verifier: crypto.verifierFor('111111')),
      );
      await repo.setCredential(
        WalletCredential(depth: 2, verifier: crypto.verifierFor('333333')),
      );

      await pinBiz.matchCredential('000000');

      // One derivation, then one AEAD attempt per slot (0..maxDepth) — the
      // empty depth-1 slot is probed with a placeholder of equal length.
      expect(crypto.masterKeyCalls.length, 1);
      expect(crypto.sealAttempts.length, maxDepth + 1);
    });

    test('returns the matched tier depth', () async {
      await repo.setCredential(
        WalletCredential(depth: 2, verifier: crypto.verifierFor('999999')),
      );

      final d = await pinBiz.matchCredential('999999');

      expect(d, 2);
    });

    test('lowest depth wins when one PIN opens several tiers', () async {
      await repo.setCredential(
        WalletCredential(depth: 0, verifier: crypto.verifierFor('123456')),
      );
      await repo.setCredential(
        WalletCredential(depth: 2, verifier: crypto.verifierFor('123456')),
      );

      expect(await pinBiz.matchCredential('123456'), 0);
    });

    test('returns null and increments attempts when nothing matches', () async {
      await repo.setPinAttempts(0);
      await repo.setCredential(
        WalletCredential(depth: 0, verifier: crypto.verifierFor('111111')),
      );

      final d = await pinBiz.matchCredential('000000');

      expect(d, isNull);
      expect(pinBiz.pinAttempts, 1);
    });

    test('caches the master key on a match, clears it on a failure', () async {
      await repo.setCredential(
        WalletCredential(depth: 0, verifier: crypto.verifierFor('123456')),
      );

      await pinBiz.matchCredential('123456');
      expect(pinBiz.lastMasterKey, 'k:123456');

      await pinBiz.matchCredential('000000');
      expect(pinBiz.lastMasterKey, isNull);
    });

    test('clearMasterKey drops a cached key', () async {
      await repo.setCredential(
        WalletCredential(depth: 0, verifier: crypto.verifierFor('123456')),
      );
      await pinBiz.matchCredential('123456');

      pinBiz.clearMasterKey();

      expect(pinBiz.lastMasterKey, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // KDF versions (ADR-007)
  // ──────────────────────────────────────────────────────────────────

  group('KDF versions', () {
    test('derives only the versions present on the device', () async {
      await repo.setCredential(WalletCredential(
        depth: 0,
        verifier: crypto.verifierFor('123456', kdfVersionArgon2id),
        kdfVersion: kdfVersionArgon2id,
      ));

      expect(await pinBiz.matchCredential('123456'), 0);
      expect(crypto.masterKeyCalls.single.version, kdfVersionArgon2id);
    });

    test('legacy and current tiers coexist during a partial upgrade', () async {
      await repo.setCredential(
        WalletCredential(depth: 0, verifier: crypto.verifierFor('111111')),
      );
      await repo.setCredential(WalletCredential(
        depth: 1,
        verifier: crypto.verifierFor('222222', kdfVersionArgon2id),
        kdfVersion: kdfVersionArgon2id,
      ));

      expect(await pinBiz.matchCredential('111111'), 0);
      expect(await pinBiz.matchCredential('222222'), 1);
      // Both versions must be derived for either PIN — the device holds both.
      expect(
        crypto.masterKeyCalls.map((c) => c.version).toSet(),
        {kdfVersionPbkdf2Legacy, kdfVersionArgon2id},
      );
    });

    test('caches the master key of the matched tier version', () async {
      await repo.setCredential(WalletCredential(
        depth: 0,
        verifier: crypto.verifierFor('123456', kdfVersionArgon2id),
        kdfVersion: kdfVersionArgon2id,
      ));

      await pinBiz.matchCredential('123456');

      expect(pinBiz.lastMasterKey, 'argon2:k:123456');
    });

    test('a legacy key does not open an Argon2id-marked verifier', () async {
      // The marker says Argon2id but the ciphertext was sealed with the legacy
      // key — a version mismatch must never authenticate.
      await repo.setCredential(WalletCredential(
        depth: 0,
        verifier: crypto.verifierFor('123456', kdfVersionPbkdf2Legacy),
        kdfVersion: kdfVersionArgon2id,
      ));

      expect(await pinBiz.matchCredential('123456'), isNull);
    });

    test('matchesAnyCredential honours the credential version', () async {
      await repo.setCredential(WalletCredential(
        depth: 0,
        verifier: crypto.verifierFor('123456', kdfVersionArgon2id),
        kdfVersion: kdfVersionArgon2id,
      ));

      expect(await pinBiz.matchesAnyCredential('123456'), isTrue);
      expect(await pinBiz.matchesAnyCredential('999999'), isFalse);
    });
  });
}
