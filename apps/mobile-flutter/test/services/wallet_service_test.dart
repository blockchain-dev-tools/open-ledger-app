/// Unit tests for [WalletService].
///
/// Covers wallet lifecycle orchestration: setup, unlock, lock, clear,
/// account management, PIN delegation, mnemonic caching, and passphrase handling.
///
/// The 3 services are hand-written mocks; the repository is a real
/// [VaultRepositoryImpl] over [InMemoryStorage]. No Rust .so required.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/account_service.dart';
import 'package:open_ledger_app/core/interfaces/mnemonic_service.dart';
import 'package:open_ledger_app/core/interfaces/pin_auth_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/data/repositories/vault_repository_impl.dart';
import 'package:open_ledger_app/infrastructure/persistence/in_memory_storage.dart';
import 'package:open_ledger_app/services/wallet_service.dart';


// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mocks
// ═══════════════════════════════════════════════════════════════════════

/// Configurable mock of [IPinAuthService].
class MockPinAuthService implements IPinAuthService {
  // ── Configurable return values ───────────────────────────────────────

  /// Return value for [randomHex].
  String randomHexResult = '00000000000000000000000000000000';

  /// Return value for [deriveKey] — the tier's vault key.
  String deriveKeyResult = 'vault-key';

  /// Return value for [encryptWithKey].
  String encryptWithKeyResult = '';

  /// Return value for [decryptWithKey] — static, used when [decryptWithKeyFn]
  /// is null.
  String decryptWithKeyResult = '';

  /// Custom decrypt callback (overrides [decryptWithKeyResult] when set).
  /// Use this when a test needs different return values for successive calls.
  String? Function(String ciphertextHex, String keyHex)? decryptWithKeyFn;

  /// Return value for [matchCredential]. `null` = no credential matches.
  int? matchCredentialResult;

  /// Return value for [matchesAnyCredential].
  bool matchesAnyCredentialResult = false;

  /// Return value for [verifyPin].
  bool verifyPinResult = true;

  /// Whether [isLocked] returns true.
  bool isLockedResult = false;

  /// Backing field for [pinAttempts].
  int _pinAttempts = 0;

  /// Master key cached by the last successful [matchCredential].
  String? _lastMasterKey;

  // ── Call recording ───────────────────────────────────────────────────

  final List<RandomHexCall> randomHexCalls = [];
  int ensureDeviceSaltCalls = 0;
  final List<String> deriveKeyCalls = [];
  final List<String> deriveKeyWithVersionCalls = [];
  final List<EncryptCall> encryptCalls = [];
  final List<EncryptCall> decryptCalls = [];
  final List<String> matchCredentialCalls = [];
  final List<String> matchesAnyCredentialCalls = [];
  final List<String> verifyPinCalls = [];
  int isLockedCalls = 0;
  int incrementPinAttemptsCalls = 0;
  int resetPinAttemptsCalls = 0;

  // ── IPinAuthService implementation ───────────────────────────────────

  @override
  String randomHex(int length) {
    randomHexCalls.add(RandomHexCall(length));
    return randomHexResult;
  }

  @override
  Future<void> ensureDeviceSalt() async {
    ensureDeviceSaltCalls++;
  }

  @override
  Future<String> deriveKey(String pin) async {
    deriveKeyCalls.add(pin);
    return deriveKeyResult;
  }

  @override
  Future<String> deriveKeyWithVersion(String pin, int version) async {
    deriveKeyWithVersionCalls.add('$pin@$version');
    return version == kdfVersionPbkdf2Legacy
        ? 'legacy-$deriveKeyResult'
        : deriveKeyResult;
  }

  @override
  String verifyKey(String masterKeyHex) => 'vk:$masterKeyHex';

  @override
  String sealVerifier(String verifyKeyHex) => 'verifier:$verifyKeyHex';

  @override
  String? get lastMasterKey => _lastMasterKey;

  @override
  void clearMasterKey() {
    _lastMasterKey = null;
  }

  @override
  String encryptWithKey(String plaintext, String keyHex) {
    encryptCalls.add(EncryptCall(plaintext, keyHex));
    return encryptWithKeyResult;
  }

  @override
  String decryptWithKey(String ciphertextHex, String keyHex) {
    decryptCalls.add(EncryptCall(ciphertextHex, keyHex));
    return decryptWithKeyFn?.call(ciphertextHex, keyHex) ??
        decryptWithKeyResult;
  }

  @override
  Future<int?> matchCredential(String pin) async {
    matchCredentialCalls.add(pin);
    final result = matchCredentialResult;
    // WalletBiz consumes [lastMasterKey] right after a successful match, so it
    // must be non-null exactly when a credential matches (and null otherwise).
    _lastMasterKey = result == null ? null : 'key-$pin';
    return result;
  }

  @override
  Future<bool> matchesAnyCredential(String pin) async {
    matchesAnyCredentialCalls.add(pin);
    return matchesAnyCredentialResult;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    verifyPinCalls.add(pin);
    return verifyPinResult;
  }

  @override
  Future<bool> isLocked() async {
    isLockedCalls++;
    return isLockedResult;
  }

  @override
  int get pinAttempts => _pinAttempts;

  @override
  int get maxPinAttempts => 5;

  @override
  Future<void> incrementPinAttempts() async {
    incrementPinAttemptsCalls++;
    _pinAttempts++;
  }

  @override
  Future<void> resetPinAttempts() async {
    resetPinAttemptsCalls++;
    _pinAttempts = 0;
  }

  void setPinAttempts(int v) => _pinAttempts = v;
}

/// Configurable mock of [IMnemonicService].
class MockMnemonicService implements IMnemonicService {
  // ── Configurable return values ───────────────────────────────────────

  String mnemonicToSeedHexResult = '';
  String fingerprintMnemonicResult = 'deadbeef';
  String generateMnemonicResult = '';
  bool validateMnemonicResult = true;
  List<String> enigmaResult = const [];

  // ── Call recording ───────────────────────────────────────────────────

  final List<SeedHexCall> seedHexCalls = [];
  final List<String> fingerprintCalls = [];
  final List<GenerateCall> generateCalls = [];
  final List<String> validateCalls = [];
  final List<EnigmaCall> enigmaCalls = [];

  // ── IMnemonicService implementation ──────────────────────────────────

  @override
  String mnemonicToSeedHex(String mnemonic, String passphrase) {
    seedHexCalls.add(SeedHexCall(mnemonic, passphrase));
    return mnemonicToSeedHexResult;
  }

  @override
  String fingerprintMnemonic(String mnemonic) {
    fingerprintCalls.add(mnemonic);
    return fingerprintMnemonicResult;
  }

  @override
  String generateMnemonic({int strength = 128}) {
    generateCalls.add(GenerateCall(strength));
    return generateMnemonicResult;
  }

  @override
  bool validateMnemonic(String mnemonic) {
    validateCalls.add(mnemonic);
    return validateMnemonicResult;
  }

  @override
  List<String> generateEnigmaMnemonic(
    String riddle,
    String secret, {
    int language = 0,
  }) {
    enigmaCalls.add(EnigmaCall(riddle, secret, language));
    return enigmaResult;
  }
}

/// Configurable mock of [IAccountService].
class MockAccountService implements IAccountService {
  // ── Configurable return values ───────────────────────────────────────

  WalletAccounts? deriveDefaultAccountsResult;
  ChainAccount? deriveSingleAccountResult;

  // ── Call recording ───────────────────────────────────────────────────

  final List<DeriveDefaultCall> deriveDefaultCalls = [];
  final List<DeriveSingleCall> deriveSingleCalls = [];
  final List<AddToListCall> addToListCalls = [];
  final List<RemoveFromListCall> removeFromListCalls = [];

  // ── IAccountService implementation ───────────────────────────────────

  @override
  Future<WalletAccounts> deriveDefaultAccounts(
      String mnemonic, String passphrase, String seedHex) async {
    deriveDefaultCalls
        .add(DeriveDefaultCall(mnemonic, passphrase, seedHex));
    return deriveDefaultAccountsResult!;
  }

  @override
  Future<ChainAccount?> deriveSingleAccount(
      String chain, String path, String seedHex) async {
    deriveSingleCalls.add(DeriveSingleCall(chain, path, seedHex));
    return deriveSingleAccountResult;
  }

  @override
  WalletAccounts addAccountToList(
      WalletAccounts accounts, ChainAccount account) {
    addToListCalls.add(AddToListCall(accounts, account));
    // Simple append — no duplicate check in mock (logic tested in
    // account_service_test.dart). WalletService does its own duplicate check.
    return accounts.copyWith(
      accounts: [...accounts.accounts, account],
    );
  }

  @override
  WalletAccounts removeAccountFromList(
      WalletAccounts accounts, String chain, String address) {
    removeFromListCalls.add(RemoveFromListCall(accounts, chain, address));
    return accounts.copyWith(
      accounts: accounts.accounts
          .where((a) => !(a.chain == chain && a.address == address))
          .toList(),
    );
  }

  @override
  Map<String, String> get defaultPaths => const {
        'ethereum': "m/44'/60'/0'/0/0",
        'solana': "m/44'/501'/0'/0'",
        'bitcoin': "m/84'/0'/0'/0/0",
        'tron': "m/44'/195'/0'/0/0",
        'sui': "m/44'/784'/0'/0'/0'",
      };
}

// ═══════════════════════════════════════════════════════════════════════
// Call record types
// ═══════════════════════════════════════════════════════════════════════

class RandomHexCall {
  final int length;
  const RandomHexCall(this.length);
}

class EncryptCall {
  final String data;
  final String keyHex;
  const EncryptCall(this.data, this.keyHex);
}

class SeedHexCall {
  final String mnemonic;
  final String passphrase;
  const SeedHexCall(this.mnemonic, this.passphrase);
}

class GenerateCall {
  final int strength;
  const GenerateCall(this.strength);
}

class EnigmaCall {
  final String riddle;
  final String secret;
  final int language;
  const EnigmaCall(this.riddle, this.secret, this.language);
}

class DeriveDefaultCall {
  final String mnemonic;
  final String passphrase;
  final String seedHex;
  const DeriveDefaultCall(this.mnemonic, this.passphrase, this.seedHex);
}

class DeriveSingleCall {
  final String chain;
  final String path;
  final String seedHex;
  const DeriveSingleCall(this.chain, this.path, this.seedHex);
}

class AddToListCall {
  final WalletAccounts accounts;
  final ChainAccount account;
  const AddToListCall(this.accounts, this.account);
}

class RemoveFromListCall {
  final WalletAccounts accounts;
  final String chain;
  final String address;
  const RemoveFromListCall(this.accounts, this.chain, this.address);
}

// ═══════════════════════════════════════════════════════════════════════
// Test helpers
// ═══════════════════════════════════════════════════════════════════════

/// Quick [ChainAccount] factory.
ChainAccount _account({
  String chain = 'ethereum',
  String address = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B',
  String path = "m/44'/60'/0'/0/0",
  String publicKey = 'cafebabe',
}) =>
    ChainAccount(
      chain: chain,
      address: address,
      derivationPath: path,
      publicKey: publicKey,
    );

/// Quick [WalletAccounts] factory.
WalletAccounts _wallet(List<ChainAccount> accounts) => WalletAccounts(
      accounts: accounts,
      mnemonicFingerprint: 'deadbeef',
    );

/// Default test accounts returned by [MockAccountService.deriveDefaultAccounts].
final _defaultAccounts = _wallet([
  _account(chain: 'ethereum'),
  _account(chain: 'solana', address: 'solana-addr', path: "m/44'/501'/0'/0'"),
  _account(chain: 'bitcoin', address: 'btc-addr', path: "m/84'/0'/0'/0/0"),
  _account(chain: 'tron', address: 'tron-addr', path: "m/44'/195'/0'/0/0"),
  _account(chain: 'sui', address: 'sui-addr', path: "m/44'/784'/0'/0'/0'"),
]);

/// Build a persisted normal vault for unlock tests.
Vault _vault({
  String id = 'v1',
  int depth = 0,
  String mnemonicEncrypted = 'enc',
  String? passphraseEncrypted,
  WalletAccounts? accounts,
}) =>
    Vault(
      id: id,
      label: '',
      depth: depth,
      mnemonicEncrypted: mnemonicEncrypted,
      passphraseEncrypted: passphraseEncrypted,
      accounts: accounts ?? const WalletAccounts(accounts: [], mnemonicFingerprint: ''),
      createdAt: 0,
    );

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  late MockPinAuthService pinAuth;
  late MockMnemonicService mnemonicService;
  late MockAccountService accountService;
  late VaultRepositoryImpl repo;
  late WalletService service;

  const testMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const testPin = '123456';
  const testPassphrase = 'my-secret-phrase';

  setUp(() {
    pinAuth = MockPinAuthService();
    mnemonicService = MockMnemonicService();
    accountService = MockAccountService();
    repo = VaultRepositoryImpl(InMemoryStorage());
    service = WalletService(
      pinAuth: pinAuth,
      mnemonicService: mnemonicService,
      accountService: accountService,
      repo: repo,
    );
  });

  /// Helper: set up wallet via [service.setupWallet] with default test values.
  /// Must be called within a test (after mocks are configured by [setUp]).
  Future<void> setup() async {
    pinAuth.deriveKeyResult = 'vault-key';
    pinAuth.encryptWithKeyResult = 'encrypted-mnemonic';
    mnemonicService.fingerprintMnemonicResult = 'deadbeef';
    mnemonicService.mnemonicToSeedHexResult =
        'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
    accountService.deriveDefaultAccountsResult = _defaultAccounts;

    await service.setupWallet(
      testMnemonic,
      pin: testPin,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 1. hasWallet delegates to repo
  // ──────────────────────────────────────────────────────────────────

  group('hasWallet', () {
    test('returns true when repo says wallet exists', () async {
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'verifier'),
      );

      final result = await service.hasWallet();

      expect(result, isTrue);
    });

    test('returns false when repo says no wallet', () async {
      final result = await service.hasWallet();

      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 2. isLocked delegates to pinAuth
  // ──────────────────────────────────────────────────────────────────

  group('isLocked', () {
    test('returns true when pinAuth says locked', () async {
      pinAuth.isLockedResult = true;

      final result = await service.isLocked();

      expect(result, isTrue);
      expect(pinAuth.isLockedCalls, 1);
    });

    test('returns false when pinAuth says not locked', () async {
      pinAuth.isLockedResult = false;

      final result = await service.isLocked();

      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 3. isUnlocked returns false initially
  // ──────────────────────────────────────────────────────────────────

  group('isUnlocked', () {
    test('returns false initially (mnemonic not cached)', () {
      expect(service.isUnlocked, isFalse);
    });

    test('returns false after lock()', () async {
      // set up a wallet so it becomes unlocked, then lock it
      await setup();
      service.lock();

      expect(service.isUnlocked, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 4. setupWallet orchestrates full flow
  // ──────────────────────────────────────────────────────────────────

  group('setupWallet', () {
    test('orchestrates full flow: salt → key → encrypt → fingerprint → '
        'seed → accounts → persist', () async {
      // Arrange
      pinAuth.deriveKeyResult = 'vault-key-hash';
      pinAuth.encryptWithKeyResult = 'encrypted-mnemonic-data';
      mnemonicService.fingerprintMnemonicResult = 'abcd1234';
      mnemonicService.mnemonicToSeedHexResult =
          'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      // Act
      final result = await service.setupWallet(
        testMnemonic,
        pin: testPin,
      );

      // Assert — device salt ensured (the PIN is stretched once over it)
      expect(pinAuth.ensureDeviceSaltCalls, 1);

      // Assert — PIN stretched into the tier's vault key
      expect(pinAuth.deriveKeyCalls, hasLength(1));
      expect(pinAuth.deriveKeyCalls.first, testPin);

      // Assert — mnemonic encrypted with the vault key
      expect(pinAuth.encryptCalls, hasLength(1));
      expect(pinAuth.encryptCalls.first.data, testMnemonic);
      expect(pinAuth.encryptCalls.first.keyHex, pinAuth.deriveKeyResult);

      // Assert — fingerprint generated
      expect(mnemonicService.fingerprintCalls, hasLength(1));
      expect(mnemonicService.fingerprintCalls.first, testMnemonic);

      // Assert — seed derived
      expect(mnemonicService.seedHexCalls, hasLength(1));
      expect(mnemonicService.seedHexCalls.first.mnemonic, testMnemonic);
      expect(mnemonicService.seedHexCalls.first.passphrase, '');

      // Assert — accounts derived
      expect(accountService.deriveDefaultCalls, hasLength(1));
      expect(
          accountService.deriveDefaultCalls.first.mnemonic, testMnemonic);
      expect(accountService.deriveDefaultCalls.first.passphrase, '');
      expect(accountService.deriveDefaultCalls.first.seedHex,
          mnemonicService.mnemonicToSeedHexResult);

      // Assert — credential stores the verifier sealed from the vault key
      final cred = await repo.getCredential(0);
      expect(cred, isNotNull);
      expect(cred!.verifier, 'verifier:vk:${pinAuth.deriveKeyResult}');

      // Assert — vault persisted
      final vault = (await repo.listVaults(depth: 0)).single;
      expect(vault.mnemonicEncrypted, 'encrypted-mnemonic-data');
      expect(vault.accounts.mnemonicFingerprint, 'abcd1234');
      expect(vault.accounts.accounts, hasLength(5));
      // storePassphrase defaults to false → nothing stored.
      expect(vault.passphraseEncrypted, isNull);

      // Assert — PIN attempts reset
      expect(pinAuth.resetPinAttemptsCalls, 1);

      // Assert — return value
      expect(result.accounts, hasLength(5));
      expect(result.mnemonicFingerprint, 'abcd1234');
    });

    test('stores passphrase when storePassphrase=true and passphrase is non-empty',
        () async {
      // Arrange
      pinAuth.deriveKeyResult = 'vault-key';
      pinAuth.encryptWithKeyResult = 'enc-mnemonic';
      mnemonicService.mnemonicToSeedHexResult = 'seed-hex';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      // Act
      await service.setupWallet(
        testMnemonic,
        pin: testPin,
        passphrase: testPassphrase,
        storePassphrase: true,
      );

      // Assert — passphrase encrypted with the same vault key
      final passphraseCall = pinAuth.encryptCalls.lastWhere(
        (c) => c.data == testPassphrase,
        orElse: () => const EncryptCall('', ''),
      );
      expect(passphraseCall.keyHex, pinAuth.deriveKeyResult);

      // Assert — passphrase persisted on the vault
      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, 'enc-mnemonic');

      // Assert — passphrase cached
      expect(service.passphrase, testPassphrase);
    });

    test('does NOT encrypt/store passphrase when storePassphrase=false', () async {
      pinAuth.deriveKeyResult = 'vault-key';
      pinAuth.encryptWithKeyResult = 'enc-mnemonic';
      mnemonicService.mnemonicToSeedHexResult = 'seed-hex';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      await service.setupWallet(
        testMnemonic,
        pin: testPin,
        passphrase: testPassphrase,
        storePassphrase: false,
      );

      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, isNull);
      expect(service.passphrase, testPassphrase);
    });

    test('does NOT cache passphrase when passphrase is empty', () async {
      pinAuth.deriveKeyResult = 'aaa';
      pinAuth.encryptWithKeyResult = 'ccc';
      mnemonicService.mnemonicToSeedHexResult = 'ddd';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      await service.setupWallet(
        testMnemonic,
        pin: testPin,
        passphrase: '',
      );

      // The active vault has no passphrase → the getter reports ''.
      expect(service.passphrase, isEmpty);
      final vault = (await repo.listVaults()).single;
      expect(vault.passphraseEncrypted, isNull);
    });

    test('passes passphrase through to mnemonicToSeedHex', () async {
      pinAuth.deriveKeyResult = 'aaa';
      pinAuth.encryptWithKeyResult = 'ccc';
      mnemonicService.mnemonicToSeedHexResult = 'ddd';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      await service.setupWallet(
        testMnemonic,
        pin: testPin,
        passphrase: 'custom-pass',
      );

      expect(mnemonicService.seedHexCalls.first.passphrase, 'custom-pass');
      expect(accountService.deriveDefaultCalls.first.passphrase, 'custom-pass');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 5. setupWallet caches mnemonic/seed/accounts in memory
  // ──────────────────────────────────────────────────────────────────

  group('setupWallet caching', () {
    test('caches mnemonic in memory', () async {
      await setup();

      expect(service.mnemonic, testMnemonic);
    });

    test('caches seedHex in memory', () async {
      // Use custom seed value — must inline setupWallet to avoid setup() overwrite
      mnemonicService.mnemonicToSeedHexResult = 'my-seed-hex';
      pinAuth.deriveKeyResult = 'vault-key';
      pinAuth.encryptWithKeyResult = 'encrypted-mnemonic';
      mnemonicService.fingerprintMnemonicResult = 'deadbeef';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      await service.setupWallet(testMnemonic, pin: testPin);

      expect(service.seedHex, 'my-seed-hex');
    });

    test('caches accounts in memory', () async {
      await setup();

      final accounts = service.getAccounts();
      expect(accounts, isNotNull);
      expect(accounts!.accounts, hasLength(5));
    });

    test('isUnlocked returns true after setup', () async {
      await setup();

      expect(service.isUnlocked, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 6. unlockWallet decrypts mnemonic and derives accounts
  // ──────────────────────────────────────────────────────────────────

  group('unlockWallet', () {
    setUp(() async {
      // Simulate a previously set-up wallet in storage
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'stored-verifier'),
      );
      await repo.saveVault(_vault(mnemonicEncrypted: 'stored-encrypted-mnemonic'));

      pinAuth.matchCredentialResult = 0;
      pinAuth.decryptWithKeyResult = testMnemonic;
      mnemonicService.mnemonicToSeedHexResult =
          'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;
    });

    test('decrypts mnemonic, derives seed, derives accounts', () async {
      final result = await service.unlockWallet(testPin);

      // Verify decryption used the master key cached by matchCredential
      expect(pinAuth.decryptCalls, hasLength(1));
      expect(pinAuth.decryptCalls.first.data, 'stored-encrypted-mnemonic');
      expect(pinAuth.decryptCalls.first.keyHex, 'key-$testPin');

      // Verify seed derivation
      expect(mnemonicService.seedHexCalls, hasLength(1));
      expect(mnemonicService.seedHexCalls.first.mnemonic, testMnemonic);

      // Verify account derivation
      expect(accountService.deriveDefaultCalls, hasLength(1));
      expect(
          accountService.deriveDefaultCalls.first.mnemonic, testMnemonic);

      // Verify PIN attempts reset
      expect(pinAuth.resetPinAttemptsCalls, 1);

      // Verify cache populated
      expect(service.mnemonic, testMnemonic);
      expect(service.seedHex, isNotNull);
      expect(service.isUnlocked, isTrue);

      // Verify return value
      expect(result.accounts, hasLength(5));
    });

    test('merges persisted extra accounts with derived defaults', () async {
      final extraAccount =
          _account(chain: 'ethereum', address: '0xExtraAddr', path: "m/44'/60'/0'/0/1");
      await repo.saveVault(_vault(
        mnemonicEncrypted: 'stored-encrypted-mnemonic',
        accounts: _wallet([extraAccount]),
      ));

      final result = await service.unlockWallet(testPin);

      // Should have 6 accounts: 5 derived defaults + 1 extra
      expect(result.accounts, hasLength(6));
      expect(result.accounts.any((a) => a.address == '0xExtraAddr'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 6b. unlockWallet loads passphrase
  // ──────────────────────────────────────────────────────────────────

  group('unlockWallet passphrase', () {
    setUp(() async {
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'verifier'),
      );
      await repo.saveVault(_vault(
        mnemonicEncrypted: 'enc',
        passphraseEncrypted: 'enc-pass',
      ));
      pinAuth.matchCredentialResult = 0;
      pinAuth.decryptWithKeyResult = testMnemonic;
      mnemonicService.mnemonicToSeedHexResult = 'seed';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;
    });

    test('loads and caches passphrase when the vault stores one', () async {
      // decryptWithKey called twice: mnemonic then passphrase
      // Use a counter to return different values
      int callCount = 0;
      pinAuth.decryptWithKeyFn = (
        String ciphertextHex,
        String keyHex,
      ) {
        callCount++;
        return callCount == 1 ? testMnemonic : 'my-saved-passphrase';
      };

      await service.unlockWallet(testPin);

      expect(service.passphrase, 'my-saved-passphrase');
      expect(service.mnemonic, testMnemonic);
    });

    test('leaves passphrase as empty string when the vault stores none',
        () async {
      await repo.saveVault(_vault(mnemonicEncrypted: 'enc'));

      await service.unlockWallet(testPin);

      expect(service.passphrase, '');
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 7. unlockWallet throws StateError when locked out
  // ──────────────────────────────────────────────────────────────────

  group('unlockWallet locked out', () {
    test('throws StateError when isLocked returns true', () async {
      pinAuth.isLockedResult = true;

      expect(
        () => service.unlockWallet(testPin),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 8. unlockWallet throws StateError when data corrupted
  // ──────────────────────────────────────────────────────────────────

  group('unlockWallet data corruption', () {
    test('throws StateError when the primary credential is missing', () async {
      pinAuth.isLockedResult = false;
      pinAuth.matchCredentialResult = 0;
      // No credential persisted.

      expect(
        () => service.unlockWallet(testPin),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when no normal vault exists', () async {
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'verifier'),
      );
      pinAuth.isLockedResult = false;
      pinAuth.matchCredentialResult = 0;

      expect(
        () => service.unlockWallet(testPin),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 9. lock clears all cached state
  // ──────────────────────────────────────────────────────────────────

  group('lock', () {
    test('clears mnemonic, seedHex, passphrase, and accounts', () async {
      await setup();
      expect(service.isUnlocked, isTrue);

      service.lock();

      expect(service.mnemonic, isNull);
      expect(service.seedHex, isNull);
      expect(service.passphrase, isNull);
      expect(service.getAccounts(), isNull);
      expect(service.isUnlocked, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 10. clearWallet wipes repo data and clears cache
  // ──────────────────────────────────────────────────────────────────

  group('clearWallet', () {
    test('wipes repo wallet data', () async {
      await setup();

      await service.clearWallet();

      expect(await repo.hasWallet(), isFalse);
      expect(await repo.listVaults(), isEmpty);
    });

    test('clears all in-memory state', () async {
      await setup();

      await service.clearWallet();

      expect(service.mnemonic, isNull);
      expect(service.seedHex, isNull);
      expect(service.passphrase, isNull);
      expect(service.getAccounts(), isNull);
      expect(service.isUnlocked, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 11. revealMnemonic returns cached mnemonic without re-decrypt
  // ──────────────────────────────────────────────────────────────────

  group('revealMnemonic', () {
    test('returns cached mnemonic when PIN is correct', () async {
      await setup();
      pinAuth.matchCredentialResult = 0;

      final result = await service.revealMnemonic(testPin);

      expect(result, testMnemonic);
      // Should have re-verified the PIN against the session credential
      expect(pinAuth.matchCredentialCalls, hasLength(1));
      expect(pinAuth.matchCredentialCalls.first, testPin);
    });

    test('returns null when no session is open (nothing cached)', () async {
      // Data exists in storage, but no session was opened → nothing cached.
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'verifier'),
      );
      await repo.saveVault(_vault(mnemonicEncrypted: 'stored-encrypted'));
      pinAuth.matchCredentialResult = 0;

      final result = await service.revealMnemonic(testPin);

      expect(result, isNull);
      expect(pinAuth.decryptCalls, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 12. revealMnemonic returns null when PIN wrong
  // ──────────────────────────────────────────────────────────────────

  group('revealMnemonic wrong PIN', () {
    test('returns null when the PIN does not match the session', () async {
      await setup();
      pinAuth.matchCredentialResult = null;

      final result = await service.revealMnemonic('wrong-pin');

      expect(result, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 13. addAccount derives and appends, checks duplicates
  // ──────────────────────────────────────────────────────────────────

  group('addAccount', () {
    setUp(() async {
      await setup();
    });

    test('derives account and appends to list', () async {
      final newAccount =
          _account(address: '0xNew', chain: 'ethereum', path: "m/44'/60'/0'/0/1");
      accountService.deriveSingleAccountResult = newAccount;

      final result =
          await service.addAccount('ethereum', "m/44'/60'/0'/0/1");

      // Verify derivation called
      expect(accountService.deriveSingleCalls, hasLength(1));
      expect(accountService.deriveSingleCalls.first.chain, 'ethereum');
      expect(
          accountService.deriveSingleCalls.first.path, "m/44'/60'/0'/0/1");

      // Verify appended
      expect(result.accounts, hasLength(6));
      expect(result.accounts.last.address, '0xNew');

      // Verify persisted
      final vault = (await repo.listVaults()).single;
      expect(vault.accounts.accounts, hasLength(6));
    });

    test('does not append duplicate (same address + chain)', () async {
      final existingAddress = _defaultAccounts.accounts.first.address;
      final duplicate = _account(
          address: existingAddress, chain: 'ethereum', path: "m/44'/60'/0'/0/0");
      accountService.deriveSingleAccountResult = duplicate;

      final result =
          await service.addAccount('ethereum', "m/44'/60'/0'/0/0");

      // Should still have 5 accounts (no duplicate added)
      expect(result.accounts, hasLength(5));
    });

    test('throws StateError when derivation fails', () async {
      accountService.deriveSingleAccountResult = null;

      expect(
        () => service.addAccount('ethereum', "m/44'/60'/0'/0/1"),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 14. addAccount throws StateError when wallet locked
  // ──────────────────────────────────────────────────────────────────

  group('addAccount locked', () {
    test('throws StateError when wallet is locked', () async {
      expect(
        () => service.addAccount('ethereum', "m/44'/60'/0'/0/0"),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 15. removeAccount filters and persists
  // ──────────────────────────────────────────────────────────────────

  group('removeAccount', () {
    setUp(() async {
      await setup();
    });

    test('removes matching account by chain + address', () async {
      final targetAddress = _defaultAccounts.accounts.first.address;

      final result = await service.removeAccount('ethereum', targetAddress);

      expect(result.accounts, hasLength(4));
      expect(
          result.accounts.any((a) => a.address == targetAddress), isFalse);

      // Verify persisted
      final vault = (await repo.listVaults()).single;
      expect(vault.accounts.accounts, hasLength(4));
    });

    test('keeps other chain accounts untouched', () async {
      final solanaCount = _defaultAccounts.accounts
          .where((a) => a.chain == 'solana')
          .length;

      await service.removeAccount('ethereum',
          _defaultAccounts.accounts.firstWhere((a) => a.chain == 'ethereum').address);

      final remaining = service.getAccounts()!;
      expect(
          remaining.accounts.where((a) => a.chain == 'solana').length,
          solanaCount);
    });

    test('throws StateError when wallet is locked', () async {
      service.lock();

      expect(
        () => service.removeAccount('ethereum', '0xAny'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 16. verifyPin delegates to pinAuth
  // ──────────────────────────────────────────────────────────────────

  group('verifyPin', () {
    test('returns true when pinAuth verifies successfully', () async {
      pinAuth.verifyPinResult = true;

      final result = await service.verifyPin(testPin);

      expect(result, isTrue);
      expect(pinAuth.verifyPinCalls, hasLength(1));
      expect(pinAuth.verifyPinCalls.first, testPin);
    });

    test('returns false when pinAuth rejects', () async {
      pinAuth.verifyPinResult = false;

      final result = await service.verifyPin('wrong-pin');

      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 17. getAccounts returns cached accounts
  // ──────────────────────────────────────────────────────────────────

  group('getAccounts', () {
    test('returns null when wallet is not set up', () {
      expect(service.getAccounts(), isNull);
    });

    test('returns cached accounts after setup', () async {
      await setup();

      final accounts = service.getAccounts();
      expect(accounts, isNotNull);
      expect(accounts!.accounts, hasLength(5));
    });

    test('returns cached accounts after unlock', () async {
      // Prepare storage state
      await repo.setCredential(
        const WalletCredential(depth: 0, verifier: 'verifier'),
      );
      await repo.saveVault(_vault(mnemonicEncrypted: 'enc'));
      pinAuth.matchCredentialResult = 0;
      pinAuth.decryptWithKeyResult = testMnemonic;
      mnemonicService.mnemonicToSeedHexResult = 'seed';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      await service.unlockWallet(testPin);

      final accounts = service.getAccounts();
      expect(accounts, isNotNull);
      expect(accounts!.accounts, hasLength(5));
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 18. mnemonic getter returns cached mnemonic
  // ──────────────────────────────────────────────────────────────────

  group('mnemonic getter', () {
    test('returns null when wallet is not set up', () {
      expect(service.mnemonic, isNull);
    });

    test('returns mnemonic after setup', () async {
      await setup();

      expect(service.mnemonic, testMnemonic);
    });

    test('returns null after lock', () async {
      await setup();
      service.lock();

      expect(service.mnemonic, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 19. seedHex getter returns cached seed
  // ──────────────────────────────────────────────────────────────────

  group('seedHex getter', () {
    test('returns null when wallet is not set up', () {
      expect(service.seedHex, isNull);
    });

    test('returns seed after setup', () async {
      // Use custom seed value — must inline setupWallet to avoid setup() overwrite
      mnemonicService.mnemonicToSeedHexResult = 'seed-value';
      pinAuth.deriveKeyResult = 'vault-key';
      pinAuth.encryptWithKeyResult = 'encrypted-mnemonic';
      mnemonicService.fingerprintMnemonicResult = 'deadbeef';
      accountService.deriveDefaultAccountsResult = _defaultAccounts;

      await service.setupWallet(testMnemonic, pin: testPin);

      expect(service.seedHex, 'seed-value');
    });

    test('returns null after lock', () async {
      await setup();
      service.lock();

      expect(service.seedHex, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // 20. incrementPinAttempts / resetPinAttempts / getPinAttempts
  // ──────────────────────────────────────────────────────────────────

  group('PIN attempt management', () {
    test('getPinAttempts delegates to pinAuth.pinAttempts', () {
      pinAuth.setPinAttempts(3);

      expect(service.getPinAttempts(), 3);
    });

    test('pinAttempts getter delegates to pinAuth', () {
      pinAuth.setPinAttempts(2);

      expect(service.pinAttempts, 2);
    });

    test('incrementPinAttempts delegates to pinAuth', () async {
      pinAuth.setPinAttempts(1);

      await service.incrementPinAttempts();

      expect(pinAuth.incrementPinAttemptsCalls, 1);
    });

    test('resetPinAttempts delegates to pinAuth', () async {
      pinAuth.setPinAttempts(4);

      await service.resetPinAttempts();

      expect(pinAuth.resetPinAttemptsCalls, 1);
    });

    test('maxPinAttempts is exposed', () {
      expect(service.maxPinAttempts, 5);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // bonus: updatePin updates the session credential + re-encrypts
  // ──────────────────────────────────────────────────────────────────

  group('updatePin', () {
    test('updates the session credential on success', () async {
      await setup();
      pinAuth.matchCredentialResult = 0;
      pinAuth.deriveKeyResult = 'new-vault-key';

      final result = await service.updatePin(testPin, '654321');

      expect(result, isTrue);
      final cred = await repo.getCredential(0);
      expect(cred!.verifier, 'verifier:vk:${pinAuth.deriveKeyResult}');
    });

    test('returns false when the old PIN does not match', () async {
      await setup();
      pinAuth.matchCredentialResult = null;

      final result = await service.updatePin(testPin, '654321');

      expect(result, isFalse);
    });

    test('re-encrypts the session mnemonic with the new PIN', () async {
      await setup();
      pinAuth.matchCredentialResult = 0;
      pinAuth.deriveKeyResult = 'new-vault-key';
      pinAuth.encryptWithKeyResult = 'reencrypted-mnemonic';

      await service.updatePin(testPin, '654321');

      final vault = (await repo.listVaults()).single;
      expect(vault.mnemonicEncrypted, 'reencrypted-mnemonic');
    });
  });
}
