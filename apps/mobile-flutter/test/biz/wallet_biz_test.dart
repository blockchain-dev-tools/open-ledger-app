/// Unit tests for [WalletBiz].
///
/// Covers setupWallet, unlockWallet, lock, clearWallet, revealMnemonic,
/// addAccount, removeAccount, updatePin (session re-encryption) and all
/// getters. Uses hand-written mocks; the repository is a real
/// [VaultRepositoryImpl] over [InMemoryStorage].
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/biz/wallet_biz.dart';
import 'package:open_ledger_app/core/interfaces/account_service.dart';
import 'package:open_ledger_app/core/interfaces/mnemonic_service.dart';
import 'package:open_ledger_app/core/interfaces/pin_auth_service.dart';
import 'package:open_ledger_app/core/interfaces/storage.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/data/repositories/vault_repository_impl.dart';
import 'package:open_ledger_app/infrastructure/persistence/in_memory_storage.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mocks
// ═══════════════════════════════════════════════════════════════════════

/// Default test accounts returned by mock deriveDefaultAccounts.
final _defaultAccounts = WalletAccounts(
  accounts: [
    const ChainAccount(
      chain: 'ethereum',
      address: '0x1234',
      derivationPath: "m/44'/60'/0'/0/0",
      publicKey: 'pubkey-eth',
    ),
    const ChainAccount(
      chain: 'solana',
      address: 'SolAddr1',
      derivationPath: "m/44'/501'/0'",
      publicKey: 'pubkey-sol',
    ),
  ],
  mnemonicFingerprint: 'test-fp',
);

/// Logical mock of [IPinAuthService].
///
/// Matching is modelled by an explicit `pin → depth` map ([credentialPins]) and
/// a [matchResult] fallback, and encryption is a configurable passthrough. That
/// keeps these tests focused on **WalletBiz orchestration** (write order,
/// cascade, wipe scope, re-encryption targets). The coupling between sealing a
/// verifier and matching it is covered by `pin_biz_test.dart` and the Rust
/// tests, not here.
class _MockPinAuth implements IPinAuthService {
  int _attempts = 0;
  bool lockedOut = false;

  // Configurable
  int? matchResult; // null = no credential matches

  /// Optional `pin → depth` map consulted *before* [matchResult]. Lets a test
  /// model several tier credentials at once.
  final Map<String, int> credentialPins = {};

  String? encryptResult;
  String? decryptResult;
  String? randomHexResult;

  /// Value reported by [lastMasterKey]; set by [matchCredential] on a match.
  String? lastMasterKeyValue;

  // Call tracking
  final List<_PinAuthCall> calls = [];

  /// Repo used to persist the device salt, mirroring the real service.
  VaultRepositoryImpl? repo;

  @override
  Future<void> ensureDeviceSalt() async {
    calls.add(_PinAuthCall('ensureDeviceSalt', []));
    final r = repo;
    if (r == null) return;
    final existing = await r.getDeviceSalt();
    if (existing == null || existing.isEmpty) {
      await r.setDeviceSalt(randomHexResult ?? '00' * 16);
    }
  }

  @override
  Future<String> deriveKey(String pin) async {
    calls.add(_PinAuthCall('deriveKey', [pin]));
    return 'key-$pin';
  }

  @override
  String verifyKey(String masterKeyHex) => 'vk:$masterKeyHex';

  @override
  String sealVerifier(String verifyKeyHex) => 'verifier:$verifyKeyHex';

  @override
  String? get lastMasterKey => lastMasterKeyValue;

  @override
  void clearMasterKey() => lastMasterKeyValue = null;

  @override
  Future<int?> matchCredential(String pin) async {
    calls.add(_PinAuthCall('matchCredential', [pin]));
    final matched =
        credentialPins.isNotEmpty ? credentialPins[pin] : matchResult;
    lastMasterKeyValue = matched == null ? null : 'key-$pin';
    return matched;
  }

  @override
  Future<bool> matchesAnyCredential(String pin) async {
    calls.add(_PinAuthCall('matchesAnyCredential', [pin]));
    // [credentialPins] is the authoritative registry of configured PINs. With
    // it empty the mock only knows that *some* PIN matches ([matchResult]) —
    // not which string — so no PIN can be asserted as already taken.
    return credentialPins.containsKey(pin);
  }

  @override
  Future<bool> verifyPin(String pin) async {
    calls.add(_PinAuthCall('verifyPin', [pin]));
    return (await matchCredential(pin)) != null;
  }

  @override
  int get pinAttempts => _attempts;

  @override
  int get maxPinAttempts => 5;

  @override
  Future<bool> isLocked() async => lockedOut;

  @override
  Future<void> incrementPinAttempts() async {
    _attempts++;
  }

  @override
  Future<void> resetPinAttempts() async {
    calls.add(_PinAuthCall('resetPinAttempts', []));
    _attempts = 0;
  }

  @override
  String encryptWithKey(String plaintext, String keyHex) {
    calls.add(_PinAuthCall('encryptWithKey', [plaintext, keyHex]));
    return encryptResult ?? 'enc-${plaintext.hashCode}';
  }

  @override
  String decryptWithKey(String ciphertextHex, String keyHex) {
    calls.add(_PinAuthCall('decryptWithKey', [ciphertextHex, keyHex]));
    return decryptResult ?? 'decrypted-content';
  }

  @override
  String randomHex(int length) {
    calls.add(_PinAuthCall('randomHex', [length]));
    return randomHexResult ?? '00' * length;
  }
}

class _MockAccountService implements IAccountService {
  WalletAccounts? deriveDefaultResult;
  ChainAccount? deriveSingleResult;

  final List<_AccountServiceCall> calls = [];
  int addAccountToListCalls = 0;
  int removeAccountFromListCalls = 0;

  @override
  Future<WalletAccounts> deriveDefaultAccounts(
      String mnemonic, String passphrase, String seedHex) async {
    calls.add(_AccountServiceCall(
        'deriveDefaultAccounts', [mnemonic, passphrase, seedHex]));
    return deriveDefaultResult ?? _defaultAccounts;
  }

  @override
  Future<ChainAccount?> deriveSingleAccount(
      String chain, String path, String seedHex) async {
    calls.add(_AccountServiceCall(
        'deriveSingleAccount', [chain, path, seedHex]));
    return deriveSingleResult;
  }

  @override
  WalletAccounts addAccountToList(
      WalletAccounts accounts, ChainAccount account) {
    addAccountToListCalls++;
    return accounts.copyWith(
      accounts: [...accounts.accounts, account],
    );
  }

  @override
  WalletAccounts removeAccountFromList(
      WalletAccounts accounts, String chain, String address) {
    removeAccountFromListCalls++;
    return accounts.copyWith(
      accounts: accounts.accounts
          .where((a) => !(a.chain == chain && a.address == address))
          .toList(),
    );
  }

  @override
  Map<String, String> get defaultPaths => {
        'ethereum': "m/44'/60'/0'/0/0",
        'solana': "m/44'/501'/0'",
        'bitcoin': "m/84'/0'/0'/0/0",
        'tron': "m/44'/195'/0'/0/0",
        'sui': "m/44'/784'/0'/0'/0",
      };
}

class _MockMnemonicService implements IMnemonicService {
  String? fingerprintResult;
  String? seedHexResult;

  final List<_MnemonicCall> calls = [];

  @override
  String generateMnemonic({int strength = 128}) =>
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  @override
  bool validateMnemonic(String mnemonic) => true;

  @override
  String mnemonicToSeedHex(String mnemonic, String passphrase) {
    calls.add(_MnemonicCall('mnemonicToSeedHex', [mnemonic, passphrase]));
    return seedHexResult ?? 'seed-hex-for-testing';
  }

  @override
  String fingerprintMnemonic(String mnemonic) {
    calls.add(_MnemonicCall('fingerprintMnemonic', [mnemonic]));
    return fingerprintResult ?? 'abc12345';
  }

  @override
  List<String> generateEnigmaMnemonic(
      String riddle, String secret, {int language = 0}) {
    return List.filled(24, 'abandon');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Call record types
// ═══════════════════════════════════════════════════════════════════════

class _PinAuthCall {
  final String method;
  final List<dynamic> args;
  const _PinAuthCall(this.method, this.args);
}

class _AccountServiceCall {
  final String method;
  final List<dynamic> args;
  const _AccountServiceCall(this.method, this.args);
}

class _MnemonicCall {
  final String method;
  final List<dynamic> args;
  const _MnemonicCall(this.method, this.args);
}

/// [Storage] wrapper that can be told to fail writes to the PIN-verifier keys,
/// modelling a persistence failure mid re-encryption (the vault write already
/// landed, the credential write blows up).
class _ToggleFailStorage implements Storage {
  final InMemoryStorage _inner = InMemoryStorage();

  /// When true, every write to a `wallet.verifier.<depth>` key throws.
  bool failVerifierWrites = false;

  @override
  Future<String?> getItem(String key) => _inner.getItem(key);

  @override
  Future<void> setItem(String key, String value) async {
    if (failVerifierWrites && key.startsWith('wallet.verifier.')) {
      throw StateError('simulated storage failure: $key');
    }
    await _inner.setItem(key, value);
  }

  @override
  Future<void> removeItem(String key) => _inner.removeItem(key);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  late _MockPinAuth pinAuth;
  late _MockAccountService accountService;
  late _MockMnemonicService mnemonicService;
  late VaultRepositoryImpl repo;
  late WalletBiz walletBiz;

  const testMnemonic = 'abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon about';
  const testPin = '123456';
  const testPassphrase = 'my secret passphrase';

  setUp(() {
    pinAuth = _MockPinAuth();
    accountService = _MockAccountService();
    mnemonicService = _MockMnemonicService();
    repo = VaultRepositoryImpl(InMemoryStorage());
    pinAuth.repo = repo;
    walletBiz = WalletBiz(
      pinAuth: pinAuth,
      accountService: accountService,
      mnemonicService: mnemonicService,
      repo: repo,
    );
  });

  // ──────────────────────────────────────────────────────────────────
  // Initial state / getters
  // ──────────────────────────────────────────────────────────────────

  group('initial state', () {
    test('isUnlocked is false initially', () {
      expect(walletBiz.isUnlocked, isFalse);
    });

    test('mnemonic is null initially', () {
      expect(walletBiz.mnemonic, isNull);
    });

    test('seedHex is null initially', () {
      expect(walletBiz.seedHex, isNull);
    });

    test('accounts is null initially', () {
      expect(walletBiz.accounts, isNull);
    });

    test('passphrase is null initially', () {
      expect(walletBiz.passphrase, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // setupWallet
  // ──────────────────────────────────────────────────────────────────

  group('setupWallet', () {
    test('full flow — salt, PIN, encrypt, seed, accounts, persist', () async {
      pinAuth.randomHexResult = 'aabbccdd';
      pinAuth.encryptResult = 'encrypted-mnemonic';
      mnemonicService.fingerprintResult = 'fp-1234';
      mnemonicService.seedHexResult = 'seed-hex-abc';

      final result = await walletBiz.setupWallet(
        testMnemonic,
        pin: testPin,
      );

      // Should return accounts with fingerprint
      expect(result.mnemonicFingerprint, 'fp-1234');

      // Should be unlocked
      expect(walletBiz.isUnlocked, isTrue);
      expect(walletBiz.mnemonic, testMnemonic);
      expect(walletBiz.seedHex, 'seed-hex-abc');

      // Repository persisted the primary verifier + one normal vault.
      final cred = await repo.getCredential(0);
      expect(cred, isNotNull);
      expect(cred!.verifier, 'verifier:vk:key-$testPin');
      expect(await repo.getDeviceSalt(), 'aabbccdd');

      final vaults = await repo.listVaults(depth: 0);
      expect(vaults, hasLength(1));
      expect(vaults.single.mnemonicEncrypted, 'encrypted-mnemonic');
      expect(vaults.single.accounts.mnemonicFingerprint, 'fp-1234');
      expect(vaults.single.accounts.accounts, hasLength(2));

      // PIN attempts reset
      expect(pinAuth.calls.any((c) => c.method == 'resetPinAttempts'), isTrue);
    });

    test('returns WalletAccounts with fingerprint', () async {
      mnemonicService.fingerprintResult = 'fp-custom';

      final result = await walletBiz.setupWallet(
        testMnemonic,
        pin: testPin,
      );

      expect(result, isA<WalletAccounts>());
      expect(result.mnemonicFingerprint, 'fp-custom');
      expect(result.accounts.length, greaterThan(0));
    });

    test('with passphrase stores encrypted passphrase', () async {
      pinAuth.randomHexResult = 'salt-hex';
      pinAuth.encryptResult = 'enc-passphrase-stored';
      mnemonicService.seedHexResult = 'seed-with-passphrase';

      await walletBiz.setupWallet(
        testMnemonic,
        pin: testPin,
        passphrase: testPassphrase,
        storePassphrase: true,
      );

      // Passphrase encrypted and persisted on the vault.
      final passEnc = pinAuth.calls.firstWhere(
        (c) => c.method == 'encryptWithKey' && c.args[0] == testPassphrase,
        orElse: () => const _PinAuthCall('', []),
      );
      expect(passEnc.method, 'encryptWithKey');

      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, 'enc-passphrase-stored');

      // Seed should be derived with passphrase
      final seedCalls = mnemonicService.calls
          .where((c) => c.method == 'mnemonicToSeedHex');
      expect(seedCalls.isNotEmpty, isTrue);
      expect(seedCalls.first.args[1], testPassphrase);

      // Passphrase should be cached
      expect(walletBiz.passphrase, testPassphrase);
    });

    test('without storePassphrase does NOT store passphrase', () async {
      pinAuth.randomHexResult = 'salt-hex';

      await walletBiz.setupWallet(
        testMnemonic,
        pin: testPin,
        passphrase: testPassphrase,
        storePassphrase: false,
      );

      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, isNull);

      // Passphrase should still be cached in memory
      expect(walletBiz.passphrase, testPassphrase);
    });

    test('empty passphrase does not store anything', () async {
      pinAuth.randomHexResult = 'salt-hex';

      await walletBiz.setupWallet(
        testMnemonic,
        pin: testPin,
        passphrase: '',
        storePassphrase: true,
      );

      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // unlockWallet
  // ──────────────────────────────────────────────────────────────────

  group('unlockWallet', () {
    setUp(() async {
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'stored-verifier'),
      );
      await repo.saveVault(Vault(
        id: 'v1',
        label: '',
        depth: 0,
        mnemonicEncrypted: 'enc-mnemonic',
        accounts: const WalletAccounts(accounts: [], mnemonicFingerprint: ''),
        createdAt: 0,
      ));
      pinAuth.matchResult = 0;
      pinAuth.decryptResult = testMnemonic;
      mnemonicService.seedHexResult = 'unlocked-seed';
    });

    test('decrypts, derives accounts, merges stored extras', () async {
      // Set up persisted extras
      final persistedExtra = const ChainAccount(
        chain: 'bitcoin',
        address: 'btc-extra',
        derivationPath: "m/84'/0'/0'/0/1",
        publicKey: 'pubkey-btc-extra',
      );
      await repo.saveVault(Vault(
        id: 'v1',
        label: '',
        depth: 0,
        mnemonicEncrypted: 'enc-mnemonic',
        accounts: WalletAccounts(
          accounts: [
            _defaultAccounts.accounts[0], // ethereum (already default)
            persistedExtra,
          ],
          mnemonicFingerprint: 'fp-extra',
        ),
        createdAt: 0,
      ));

      final result = await walletBiz.unlockWallet(testPin);

      expect(walletBiz.isUnlocked, isTrue);
      expect(walletBiz.mnemonic, testMnemonic);
      expect(walletBiz.seedHex, 'unlocked-seed');

      // Should contain both default accounts + the extra
      expect(result.accounts.length, 3);
      expect(result.accounts.any((a) =>
          a.chain == 'bitcoin' && a.address == 'btc-extra'), isTrue);

      // PIN attempts reset
      expect(pinAuth.calls.any((c) => c.method == 'resetPinAttempts'), isTrue);
    });

    test('throws when locked out', () async {
      pinAuth.lockedOut = true;

      expect(
        () => walletBiz.unlockWallet(testPin),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when the primary credential is missing', () async {
      await repo.deleteCredential(0);

      expect(
        () => walletBiz.unlockWallet(testPin),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when no vault is stored', () async {
      await repo.deleteVault('v1');

      expect(
        () => walletBiz.unlockWallet(testPin),
        throwsA(isA<StateError>()),
      );
    });

    test('loads stored passphrase when the vault has one', () async {
      await repo.saveVault(Vault(
        id: 'v1',
        label: '',
        depth: 0,
        mnemonicEncrypted: 'enc-mnemonic',
        passphraseEncrypted: 'enc-pass',
        accounts: const WalletAccounts(accounts: [], mnemonicFingerprint: ''),
        createdAt: 0,
      ));

      await walletBiz.unlockWallet(testPin);

      // The decryptCalls should include a call with enc-pass
      final decryptCalls = pinAuth.calls
          .where((c) => c.method == 'decryptWithKey');
      expect(decryptCalls.length, greaterThanOrEqualTo(2));
      expect(decryptCalls.any((c) => c.args[0] == 'enc-pass'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // lock / clearWallet
  // ──────────────────────────────────────────────────────────────────

  group('lock', () {
    test('clears cached mnemonic, seed, accounts, passphrase', () async {
      // First set up
      await walletBiz.setupWallet(testMnemonic, pin: testPin);
      expect(walletBiz.isUnlocked, isTrue);

      walletBiz.lock();

      expect(walletBiz.isUnlocked, isFalse);
      expect(walletBiz.mnemonic, isNull);
      expect(walletBiz.seedHex, isNull);
      expect(walletBiz.accounts, isNull);
      expect(walletBiz.passphrase, isNull);
    });
  });

  group('clearWallet', () {
    test('clears all repo data + cache', () async {
      await walletBiz.setupWallet(testMnemonic, pin: testPin);

      await walletBiz.clearWallet();

      expect(await repo.hasWallet(), isFalse);
      expect(await repo.listVaults(), isEmpty);
      expect(walletBiz.isUnlocked, isFalse);
      expect(walletBiz.mnemonic, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // revealMnemonic
  // ──────────────────────────────────────────────────────────────────

  group('revealMnemonic', () {
    test('correct PIN returns cached mnemonic when unlocked', () async {
      await walletBiz.setupWallet(testMnemonic, pin: testPin);
      pinAuth.matchResult = 0; // PIN must match

      final result = await walletBiz.revealMnemonic(testPin);

      expect(result, testMnemonic);
    });

    test('wrong PIN returns null', () async {
      await walletBiz.setupWallet(testMnemonic, pin: testPin);
      pinAuth.matchResult = null; // PIN won't match

      final result = await walletBiz.revealMnemonic('wrong');
      expect(result, isNull);
    });

    test('returns null when wallet is locked and data missing', () async {
      // Locked state without any persisted data
      pinAuth.matchResult = 0; // PIN match, but no session

      final result = await walletBiz.revealMnemonic(testPin);
      expect(result, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // addAccount
  // ──────────────────────────────────────────────────────────────────

  group('addAccount', () {
    test('derives, adds, persists', () async {
      await walletBiz.setupWallet(testMnemonic, pin: testPin);

      const newAccount = ChainAccount(
        chain: 'bitcoin',
        address: 'btc-new',
        derivationPath: "m/84'/0'/0'/0/1",
        publicKey: 'pubkey-btc',
      );
      accountService.deriveSingleResult = newAccount;

      final result = await walletBiz.addAccount('bitcoin', "m/84'/0'/0'/0/1");

      expect(result.accounts.length, 3); // 2 defaults + 1 new
      expect(result.accounts.any((a) => a.address == 'btc-new'), isTrue);

      final vault = (await repo.listVaults()).single;
      expect(vault.accounts.accounts, hasLength(3));
    });

    test('rejects duplicates', () async {
      await walletBiz.setupWallet(testMnemonic, pin: testPin);

      // Try to add an account that already exists
      accountService.deriveSingleResult = _defaultAccounts.accounts[0];

      final result = await walletBiz.addAccount('ethereum', "m/44'/60'/0'/0/0");

      expect(result.accounts.length, 2); // unchanged
    });

    test('throws when locked', () async {
      expect(
        () => walletBiz.addAccount('ethereum', "m/44'/60'/0'/0/0"),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // removeAccount
  // ──────────────────────────────────────────────────────────────────

  group('removeAccount', () {
    test('removes account and persists', () async {
      await walletBiz.setupWallet(testMnemonic, pin: testPin);

      final result = await walletBiz.removeAccount(
          'ethereum', '0x1234');

      expect(result.accounts.length, 1); // only solana remains

      final vault = (await repo.listVaults()).single;
      expect(vault.accounts.accounts, hasLength(1));
    });

    test('throws when locked', () async {
      expect(
        () => walletBiz.removeAccount('ethereum', '0x1234'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // updatePin (session-scoped: re-encrypts every vault of the session)
  // ──────────────────────────────────────────────────────────────────

  group('updatePin', () {
    const oldPin = '111111';
    const newPin = '222222';

    /// Set up a primary session; optionally store a passphrase.
    Future<void> setup({bool withPassphrase = false}) async {
      pinAuth.randomHexResult = 'old-salt';
      pinAuth.encryptResult = 'encrypted-value';
      mnemonicService.seedHexResult = 'seed';
      await walletBiz.setupWallet(
        testMnemonic,
        pin: oldPin,
        passphrase: withPassphrase ? testPassphrase : '',
        storePassphrase: withPassphrase,
      );
    }

    test('returns false when the old PIN does not match the session',
        () async {
      await setup();
      pinAuth.matchResult = null; // nothing matches

      final result = await walletBiz.updatePin(oldPin, newPin);

      expect(result, isFalse);
    });

    test('returns false when the wallet is locked', () async {
      pinAuth.matchResult = 0;

      final result = await walletBiz.updatePin(oldPin, newPin);

      expect(result, isFalse);
    });

    test('returns true on success, rewrites the verifier', () async {
      await setup();
      pinAuth.matchResult = 0;

      final result = await walletBiz.updatePin(oldPin, newPin);

      expect(result, isTrue);
      // New credential persisted; the device salt is shared and unchanged.
      final cred = await repo.getCredential(0);
      expect(cred!.verifier, 'verifier:vk:key-$newPin');
    });

    test('re-encrypts the session mnemonic with the new PIN', () async {
      await setup();
      pinAuth.matchResult = 0;
      pinAuth.randomHexResult = 'new-salt';
      pinAuth.encryptResult = 'reencrypted-mnemonic';

      await walletBiz.updatePin(oldPin, newPin);

      // Re-encryption used the new PIN + fresh salt.
      final reEncrypt = pinAuth.calls.firstWhere(
        (c) =>
            c.method == 'encryptWithKey' &&
            c.args[0] == testMnemonic &&
            c.args[1] == 'key-$newPin',
        orElse: () => const _PinAuthCall('', []),
      );
      expect(reEncrypt.method, 'encryptWithKey');
      expect(reEncrypt.args[1], 'key-$newPin');

      // Persisted.
      final vault = (await repo.listVaults()).single;
      expect(vault.mnemonicEncrypted, 'reencrypted-mnemonic');
    });

    test('re-encrypts the stored passphrase with the new PIN', () async {
      await setup(withPassphrase: true);
      pinAuth.matchResult = 0;
      pinAuth.randomHexResult = 'new-salt';
      pinAuth.encryptResult = 'reencrypted-passphrase';

      await walletBiz.updatePin(oldPin, newPin);

      final passEnc = pinAuth.calls.firstWhere(
        (c) =>
            c.method == 'encryptWithKey' &&
            c.args[0] == testPassphrase &&
            c.args[1] == 'key-$newPin',
        orElse: () => const _PinAuthCall('', []),
      );
      expect(passEnc.method, 'encryptWithKey');
      expect(passEnc.args[1], 'key-$newPin');

      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, 'reencrypted-passphrase');
    });

    test('does NOT re-encrypt a passphrase when none is stored', () async {
      await setup();
      pinAuth.matchResult = 0;
      pinAuth.randomHexResult = 'new-salt';
      pinAuth.encryptResult = 'reencrypted-mnemonic';

      await walletBiz.updatePin(oldPin, newPin);

      expect(
        pinAuth.calls.any(
            (c) => c.method == 'encryptWithKey' && c.args[0] == testPassphrase),
        isFalse,
      );
      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Stand-in wallet (ADR-009): configure / update / remove
  // ──────────────────────────────────────────────────────────────────

  group('stand-in wallet', () {
    const mainPin = '123456';
    const standInPin = '654321';
    const nestedPin = '777777';
    const standInMnemonic = 'legal winner thank year wave sausage worth useful '
        'legal winner thank year wave sausage worth useful legal winner thank '
        'year wave sausage worth title';

    /// Open a depth-0 session with one vault; model the primary PIN.
    Future<void> setupPrimary() async {
      pinAuth.credentialPins[mainPin] = 0;
      pinAuth.decryptResult = testMnemonic;
      await walletBiz.setupWallet(testMnemonic, pin: mainPin);
    }

    /// Configure the depth-1 stand-in from the depth-0 session.
    Future<void> configure({StandInMode mode = StandInMode.hide}) async {
      pinAuth.randomHexResult = 'standin-salt';
      pinAuth.encryptResult = 'enc-hidden';
      await walletBiz.configureStandIn(
        standInMnemonic,
        pin: standInPin,
        mainPin: mainPin,
        mode: mode,
      );
      pinAuth.credentialPins[standInPin] = 1;
    }

    /// Configure the depth-2 stand-in from the depth-1 session (nesting).
    Future<void> configureNested({StandInMode mode = StandInMode.hide}) async {
      pinAuth.randomHexResult = 'nested-salt';
      pinAuth.encryptResult = 'enc-nested';
      await walletBiz.configureStandIn(
        standInMnemonic,
        pin: nestedPin,
        mainPin: standInPin,
        mode: mode,
      );
      pinAuth.credentialPins[nestedPin] = 2;
    }

    test('configureStandIn creates the child credential, vault and mode',
        () async {
      await setupPrimary();

      await configure();

      final cred = await repo.getCredential(1);
      expect(cred, isNotNull);
      expect(cred!.verifier, 'verifier:vk:key-$standInPin');
      expect(await walletBiz.hasStandIn(), isTrue);
      expect(await walletBiz.standInMode(), StandInMode.hide);

      final hidden = await repo.listVaults(depth: 1);
      expect(hidden, hasLength(1));
      expect(hidden.single.mnemonicEncrypted, 'enc-hidden');
      // The primary vault is untouched.
      expect(await repo.listVaults(depth: 0), hasLength(1));
    });

    test('the stand-in PIN opens a stand-in session with only the hidden vault',
        () async {
      await setupPrimary();
      await configure();
      walletBiz.lock();

      final accounts = await walletBiz.unlockWallet(standInPin);

      expect(accounts, isNotNull);
      expect(walletBiz.isStandInSession, isTrue);
      expect(walletBiz.sessionDepth, 1);
      expect(walletBiz.vaults, hasLength(1));
      expect(walletBiz.vaults.single.isHidden, isTrue);
      expect(walletBiz.lastUnlockWiped, isFalse);
    });

    test('configureStandIn from a stand-in session nests one tier deeper',
        () async {
      await setupPrimary();
      await configure();
      walletBiz.lock();
      await walletBiz.unlockWallet(standInPin);

      await configureNested();

      expect(await repo.getCredential(2), isNotNull);
      expect(await repo.listVaults(depth: 2), hasLength(1));
    });

    test('hasStandIn is session-relative (reports the child tier only)',
        () async {
      await setupPrimary();
      await configure();
      walletBiz.lock();
      await walletBiz.unlockWallet(standInPin);

      // The depth-1 session has no depth-2 child, so it must report false even
      // though the depth-1 credential itself exists — otherwise a stand-in
      // session would wrongly display "Set up" in Settings.
      expect(await walletBiz.hasStandIn(), isFalse);

      await configureNested();
      expect(await walletBiz.hasStandIn(), isTrue);
    });

    test('configureStandIn rejects a stand-in PIN equal to any existing PIN',
        () async {
      await setupPrimary();

      expect(
        () => walletBiz.configureStandIn(
          standInMnemonic,
          pin: mainPin,
          mainPin: mainPin,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('configureStandIn rejects a second configuration', () async {
      await setupPrimary();
      await configure();

      expect(
        () => walletBiz.configureStandIn(
          standInMnemonic,
          pin: '111111',
          mainPin: mainPin,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('updateStandInPin swaps the salt/hash and re-encrypts the hidden vault',
        () async {
      await setupPrimary();
      await configure();
      final before = (await repo.getCredential(1))!;

      pinAuth.randomHexResult = 'new-standin-salt';
      pinAuth.encryptResult = 'reencrypted-hidden';
      await walletBiz.updateStandInPin(oldPin: standInPin, newPin: '111111');

      final after = (await repo.getCredential(1))!;
      expect(after.verifier, 'verifier:vk:key-111111');
      expect(after.verifier, isNot(before.verifier));
      final hidden = await repo.listVaults(depth: 1);
      expect(hidden.single.mnemonicEncrypted, 'reencrypted-hidden');

      // The new stand-in PIN unlocks; the old one no longer matches.
      pinAuth.credentialPins['111111'] = 1;
      pinAuth.credentialPins.remove(standInPin);
      walletBiz.lock();
      await walletBiz.unlockWallet('111111');
      expect(walletBiz.isStandInSession, isTrue);

      walletBiz.lock();
      expect(
        () => walletBiz.unlockWallet(standInPin),
        throwsA(isA<StateError>()),
      );
    });

    test('updateStandInMode changes the mode with the current session PIN',
        () async {
      await setupPrimary();
      await configure();

      await walletBiz.updateStandInMode(
        pin: mainPin,
        mode: StandInMode.wipe,
      );

      expect(await walletBiz.standInMode(), StandInMode.wipe);
    });

    test('updateStandInMode rejects a wrong PIN', () async {
      await setupPrimary();
      await configure();

      expect(
        () => walletBiz.updateStandInMode(
          pin: '000000',
          mode: StandInMode.wipe,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await walletBiz.standInMode(), StandInMode.hide);
    });

    test('removeStandIn drops the child vault but keeps the parent tier',
        () async {
      await setupPrimary();
      await configure();
      expect(await repo.listVaults(depth: 0), hasLength(1));

      await walletBiz.removeStandIn(pin: mainPin);

      expect(await repo.getCredential(1), isNull);
      expect(await repo.listVaults(depth: 1), isEmpty);
      expect(await repo.listVaults(depth: 0), hasLength(1));
      expect(await walletBiz.standInMode(), StandInMode.hide);
    });

    test('wipe mode erases the replaced tier on stand-in unlock', () async {
      await setupPrimary();
      await configure(mode: StandInMode.wipe);
      walletBiz.lock();

      await walletBiz.unlockWallet(standInPin);

      expect(walletBiz.isStandInSession, isTrue);
      expect(walletBiz.lastUnlockWiped, isTrue);
      expect(await repo.listVaults(depth: 0), isEmpty);
      expect(await repo.listVaults(depth: 1), hasLength(1));
      // Mode resets once there is nothing left to erase.
      expect(await walletBiz.standInMode(), StandInMode.hide);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Depth tiers (nesting): visibility, wipe scope, addVault, clearWallet
  // ──────────────────────────────────────────────────────────────────

  group('depth tiers', () {
    const mainPin = '123456';
    const standInPin = '654321';
    const nestedPin = '777777';
    const standInMnemonic = 'legal winner thank year wave sausage worth useful '
        'legal winner thank year wave sausage worth useful legal winner thank '
        'year wave sausage worth title';
    const thirdMnemonic = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';

    Future<void> setupPrimary() async {
      pinAuth.credentialPins[mainPin] = 0;
      pinAuth.decryptResult = testMnemonic;
      await walletBiz.setupWallet(testMnemonic, pin: mainPin);
    }

    Future<void> configure({StandInMode mode = StandInMode.hide}) async {
      pinAuth.randomHexResult = 'standin-salt';
      pinAuth.encryptResult = 'enc-hidden';
      await walletBiz.configureStandIn(
        standInMnemonic,
        pin: standInPin,
        mainPin: mainPin,
        mode: mode,
      );
      pinAuth.credentialPins[standInPin] = 1;
    }

    Future<void> configureNested({StandInMode mode = StandInMode.hide}) async {
      pinAuth.randomHexResult = 'nested-salt';
      pinAuth.encryptResult = 'enc-nested';
      await walletBiz.configureStandIn(
        standInMnemonic,
        pin: nestedPin,
        mainPin: standInPin,
        mode: mode,
      );
      pinAuth.credentialPins[nestedPin] = 2;
    }

    /// Build a full three-tier device and open a depth-1 session.
    Future<void> buildThreeTiers({StandInMode nestedMode = StandInMode.hide}) async {
      await setupPrimary();
      await configure();
      walletBiz.lock();
      await walletBiz.unlockWallet(standInPin);
      await configureNested(mode: nestedMode);
    }

    test('test 1 — the depth-2 PIN unlocks only the depth-2 tier', () async {
      await buildThreeTiers();
      walletBiz.lock();

      await walletBiz.unlockWallet(nestedPin);

      expect(walletBiz.sessionDepth, 2);
      expect(walletBiz.vaults, hasLength(1));
      expect(walletBiz.vaults.every((v) => v.depth == 2), isTrue);
      // Shallower tiers stay out of the session.
      expect(walletBiz.vaults.any((v) => v.depth == 0), isFalse);
      expect(walletBiz.vaults.any((v) => v.depth == 1), isFalse);
    });

    test('test 2 — wipe at depth 2 erases depth 1 only, depth 0 survives',
        () async {
      await buildThreeTiers(nestedMode: StandInMode.wipe);
      walletBiz.lock();

      await walletBiz.unlockWallet(nestedPin);

      expect(walletBiz.lastUnlockWiped, isTrue);
      // depth 1 destroyed (vault + credential).
      expect(await repo.getCredential(1), isNull);
      expect(await repo.listVaults(depth: 1), isEmpty);
      // depth 2 (the session) and depth 0 both survive.
      expect(await repo.getCredential(2), isNotNull);
      expect(await repo.listVaults(depth: 2), hasLength(1));
      expect(await repo.getCredential(0), isNotNull);
      expect(await repo.listVaults(depth: 0), hasLength(1));
    });

    test('test 3 — addVault succeeds in a stand-in session', () async {
      await setupPrimary();
      await configure();
      walletBiz.lock();
      await walletBiz.unlockWallet(standInPin);

      await walletBiz.addVault(thirdMnemonic, pin: standInPin);

      expect(await repo.listVaults(depth: 1), hasLength(2));
      expect(walletBiz.vaults, hasLength(2));
      expect(walletBiz.vaults.every((v) => v.depth == 1), isTrue);
    });

    test('test 5 — the two-vault cap still applies to depth 0', () async {
      await setupPrimary();
      expect(walletBiz.sessionDepth, 0);

      await walletBiz.addVault(thirdMnemonic, pin: mainPin);
      expect(await repo.listVaults(depth: 0), hasLength(2));

      // A *new* wallet at the cap must fail on the limit, not on duplication.
      expect(
        () => walletBiz.addVault(standInMnemonic, pin: mainPin),
        throwsA(predicate((e) =>
            e is StateError && e.message.toString().contains('Vault limit'))),
      );
    });

    test('addVault rejects a wallet already in this tier', () async {
      await setupPrimary();

      expect(
        () => walletBiz.addVault(testMnemonic, pin: mainPin),
        throwsA(predicate((e) =>
            e is StateError &&
            e.message.toString().contains('already in this tier'))),
      );
      expect(await repo.listVaults(depth: 0), hasLength(1));
    });

    test('addVault allows the same mnemonic under a different passphrase',
        () async {
      await setupPrimary();

      // Two passphrases of one mnemonic are two different wallets.
      await walletBiz.addVault(testMnemonic, pin: mainPin, passphrase: 'other');

      expect(await repo.listVaults(depth: 0), hasLength(2));
    });

    test('updatePin refuses a PIN already used by another tier', () async {
      await setupPrimary();
      await configure();

      expect(
        () => walletBiz.updatePin(mainPin, standInPin),
        throwsA(predicate((e) =>
            e is StateError &&
            e.message.toString().contains('already in use'))),
      );
      // The first tier's credential is left untouched.
      expect(await repo.getCredential(0), isNotNull);
    });

    test('test 6 — clearWallet clears the current tier and deeper, not shallower',
        () async {
      await buildThreeTiers();
      expect(walletBiz.sessionDepth, 1);

      await walletBiz.clearWallet();

      // depth 1 (session) and depth 2 (its child) are gone.
      expect(await repo.getCredential(1), isNull);
      expect(await repo.getCredential(2), isNull);
      expect(await repo.listVaults(depth: 1), isEmpty);
      expect(await repo.listVaults(depth: 2), isEmpty);
      // depth 0 is untouched.
      expect(await repo.getCredential(0), isNotNull);
      expect(await repo.listVaults(depth: 0), hasLength(1));
      expect(walletBiz.isUnlocked, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // onVaultsDestroyed (drives signing-history cleanup)
  // ──────────────────────────────────────────────────────────────────

  group('onVaultsDestroyed', () {
    const mainPin = '123456';
    const standInPin = '654321';
    const nestedPin = '777777';
    const standInMnemonic = 'legal winner thank year wave sausage worth useful '
        'legal winner thank year wave sausage worth useful legal winner thank '
        'year wave sausage worth title';
    const thirdMnemonic = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';

    Future<void> setupPrimary() async {
      pinAuth.credentialPins[mainPin] = 0;
      pinAuth.decryptResult = testMnemonic;
      await walletBiz.setupWallet(testMnemonic, pin: mainPin);
    }

    Future<void> configureStandIn({StandInMode mode = StandInMode.hide}) async {
      pinAuth.randomHexResult = 'standin-salt';
      pinAuth.encryptResult = 'enc-hidden';
      await walletBiz.configureStandIn(
        standInMnemonic,
        pin: standInPin,
        mainPin: mainPin,
        mode: mode,
      );
      pinAuth.credentialPins[standInPin] = 1;
    }

    test('removeVault reports the removed vault id', () async {
      await setupPrimary();
      await walletBiz.addVault(thirdMnemonic, pin: mainPin);
      final target = walletBiz.vaults.last.id;

      final destroyed = <Set<String>>[];
      walletBiz.onVaultsDestroyed = destroyed.add;

      await walletBiz.removeVault(target, pin: mainPin);

      expect(destroyed, hasLength(1));
      expect(destroyed.single, {target});
    });

    test('removeStandIn reports the child tier\'s vault ids', () async {
      await setupPrimary();
      await configureStandIn();
      final childId = (await repo.listVaults(depth: 1)).single.id;

      final destroyed = <Set<String>>[];
      walletBiz.onVaultsDestroyed = destroyed.add;

      await walletBiz.removeStandIn(pin: mainPin);

      expect(destroyed, hasLength(1));
      expect(destroyed.single, {childId});
    });

    test('a wipe unlock reports the erased tier\'s vault ids', () async {
      await setupPrimary();
      await configureStandIn(mode: StandInMode.wipe);
      final primaryId = (await repo.listVaults(depth: 0)).single.id;

      walletBiz.lock();
      final destroyed = <Set<String>>[];
      walletBiz.onVaultsDestroyed = destroyed.add;

      await walletBiz.unlockWallet(standInPin);

      expect(destroyed, hasLength(1));
      expect(destroyed.single, {primaryId});
    });

    test('clearWallet reports every cleared tier\'s vault ids', () async {
      await setupPrimary();
      await configureStandIn();
      walletBiz.lock();
      await walletBiz.unlockWallet(standInPin);

      pinAuth.randomHexResult = 'nested-salt';
      pinAuth.encryptResult = 'enc-nested';
      await walletBiz.configureStandIn(
        standInMnemonic,
        pin: nestedPin,
        mainPin: standInPin,
      );
      pinAuth.credentialPins[nestedPin] = 2;

      final expected = <String>{
        ...(await repo.listVaults(depth: 1)).map((v) => v.id),
        ...(await repo.listVaults(depth: 2)).map((v) => v.id),
      };

      final destroyed = <Set<String>>[];
      walletBiz.onVaultsDestroyed = destroyed.add;

      // The depth-1 session clears its own tier and the depth-2 child.
      await walletBiz.clearWallet();

      expect(destroyed.expand((s) => s).toSet(), expected);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Re-encryption rollback (updatePin / updateStandInPin)
  // ──────────────────────────────────────────────────────────────────

  group('re-encryption rollback', () {
    const mainPin = '123456';
    const standInPin = '654321';
    const standInMnemonic = 'legal winner thank year wave sausage worth useful '
        'legal winner thank year wave sausage worth useful legal winner thank '
        'year wave sausage worth title';

    late _ToggleFailStorage storage;
    late VaultRepositoryImpl failRepo;
    late WalletBiz biz;

    setUp(() {
      storage = _ToggleFailStorage();
      failRepo = VaultRepositoryImpl(storage);
      pinAuth.repo = failRepo;
      biz = WalletBiz(
        pinAuth: pinAuth,
        accountService: accountService,
        mnemonicService: mnemonicService,
        repo: failRepo,
      );
    });

    test('updatePin rolls the vault back when the credential write fails',
        () async {
      pinAuth.credentialPins[mainPin] = 0;
      pinAuth.encryptResult = 'original-cipher';
      mnemonicService.seedHexResult = 'seed';
      await biz.setupWallet(testMnemonic, pin: mainPin);
      final originalVerifier = (await failRepo.getCredential(0))!.verifier;

      // The vault write lands, then the credential write blows up.
      pinAuth.encryptResult = 'reencrypted-cipher';
      storage.failVerifierWrites = true;

      await expectLater(
        biz.updatePin(mainPin, '222222'),
        throwsA(isA<StateError>()),
      );

      // Compensating write: the vault keeps its pre-change ciphertext...
      expect(
        (await failRepo.listVaults()).single.mnemonicEncrypted,
        'original-cipher',
      );
      // ...and the tier keeps its original credential.
      expect((await failRepo.getCredential(0))!.verifier, originalVerifier);
    });

    test('updateStandInPin rolls the hidden vault back on credential failure',
        () async {
      pinAuth.credentialPins[mainPin] = 0;
      pinAuth.decryptResult = testMnemonic;
      mnemonicService.seedHexResult = 'seed';
      await biz.setupWallet(testMnemonic, pin: mainPin);

      pinAuth.randomHexResult = 'standin-salt';
      pinAuth.encryptResult = 'enc-hidden-original';
      await biz.configureStandIn(
        standInMnemonic,
        pin: standInPin,
        mainPin: mainPin,
      );
      pinAuth.credentialPins[standInPin] = 1;
      final originalVerifier = (await failRepo.getCredential(1))!.verifier;

      pinAuth.encryptResult = 'enc-hidden-reencrypted';
      storage.failVerifierWrites = true;

      await expectLater(
        biz.updateStandInPin(oldPin: standInPin, newPin: '111111'),
        throwsA(isA<StateError>()),
      );

      final hidden = await failRepo.listVaults(depth: 1);
      expect(hidden.single.mnemonicEncrypted, 'enc-hidden-original');
      expect((await failRepo.getCredential(1))!.verifier, originalVerifier);
    });
  });
}
