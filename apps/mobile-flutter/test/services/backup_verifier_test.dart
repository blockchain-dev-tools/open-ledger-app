/// Unit tests for [BackupVerifier] (ADR-011 §5).
///
/// The verifier recomputes the active vault's derived output and compares it
/// to a retyped secret. These tests pin the three paths (mnemonic /
/// passphrase / Enigma) plus the "unavailable" guards, using fakes of the
/// `core/interfaces/` abstractions only (no Rust .so).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/backup_verifier.dart';
import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/services/backup_verifier.dart';

const _path = "m/44'/60'/0'/0/0";
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';
const _phrase = 'legal winner thank year wave sausage worth useful legal '
    'winner thank yellow';

/// Deterministic pseudo-crypto: seeds and addresses are pure functions of
/// their inputs, so a test can compute the expected baseline up front.
class _FakeCrypto implements ICryptoService {
  bool validateResult = true;
  bool nullSeed = false;
  bool nullAddress = false;
  String? enigmaPhrase;

  final List<({String riddle, String secret, int language})> enigmaCalls = [];

  static String seedFor(String mnemonic, String passphrase) =>
      'seed|$mnemonic|$passphrase';

  static String addressFor(String seed, String path) => 'addr|$seed|$path';

  @override
  bool validateMnemonic(String mnemonic) => validateResult;

  @override
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) =>
      nullSeed ? null : seedFor(mnemonic, passphrase);

  @override
  String? deriveEthAddress(String seedHex, String path) =>
      nullAddress ? null : addressFor(seedHex, path);

  @override
  String? enigmaDeriveMnemonic(String riddle, String secret, int language) {
    enigmaCalls.add((riddle: riddle, secret: secret, language: language));
    return enigmaPhrase;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Minimal wallet view: only the members [BackupVerifier] reads.
class _FakeWallet implements IWalletService {
  Vault? vault;
  String? mnemonicValue;
  String? passphraseValue = '';
  WalletAccounts? accountsValue;

  @override
  Vault? get activeVault => vault;

  @override
  String? get mnemonic => mnemonicValue;

  @override
  String? get passphrase => passphraseValue;

  @override
  WalletAccounts? getAccounts() => accountsValue;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// ETH account whose address is the verifier's expected baseline for
/// ([mnemonic], [passphrase]).
ChainAccount _ethAccount(String mnemonic, String passphrase) => ChainAccount(
      address: _FakeCrypto.addressFor(
        _FakeCrypto.seedFor(mnemonic, passphrase),
        _path,
      ),
      derivationPath: _path,
      publicKey: '',
      chain: 'ethereum',
    );

WalletAccounts _accounts(List<ChainAccount> accounts) =>
    WalletAccounts(accounts: accounts, mnemonicFingerprint: 'fp');

Vault _vault({VaultSource source = VaultSource.imported, int enigmaLanguage = 0}) =>
    Vault(
      id: 'v1',
      label: '',
      depth: 0,
      mnemonicEncrypted: 'ciphertext',
      accounts: _accounts(const []),
      createdAt: 0,
      source: source,
      enigmaLanguage: enigmaLanguage,
    );

void main() {
  late _FakeCrypto crypto;
  late _FakeWallet wallet;
  late BackupVerifier verifier;

  /// Unlocked non-Enigma vault whose ETH baseline matches ([mnemonic], [passphrase]).
  void setUpUnlocked({String passphrase = ''}) {
    wallet
      ..vault = _vault()
      ..mnemonicValue = _mnemonic
      ..passphraseValue = passphrase
      ..accountsValue = _accounts([_ethAccount(_mnemonic, passphrase)]);
  }

  setUp(() {
    crypto = _FakeCrypto();
    wallet = _FakeWallet();
    verifier = BackupVerifier(wallet: wallet, crypto: crypto);
  });

  group('verifyMnemonic', () {
    test('matches the re-typed phrase (normalized)', () async {
      setUpUnlocked();

      // Whitespace (newlines, double spaces, surrounding) is collapsed first.
      final messy = '  $_mnemonic\n';
      expect(await verifier.verifyMnemonic(messy), VerifyResult.match);
    });

    test('mismatches a valid but wrong phrase', () async {
      setUpUnlocked();

      expect(await verifier.verifyMnemonic(_phrase), VerifyResult.mismatch);
    });

    test('mismatches an invalid phrase without deriving', () async {
      setUpUnlocked();
      crypto.validateResult = false;

      expect(await verifier.verifyMnemonic('not a real phrase'),
          VerifyResult.mismatch);
    });

    test('uses the session passphrase when recomputing the seed', () async {
      setUpUnlocked(passphrase: 'my-pass');
      // Baseline was built with 'my-pass'; a verify that ignored the session
      // passphrase would derive a different address and mismatch.
      expect(await verifier.verifyMnemonic(_mnemonic), VerifyResult.match);
    });

    test('unavailable while locked', () async {
      setUpUnlocked();
      wallet.mnemonicValue = null;

      expect(await verifier.verifyMnemonic(_mnemonic),
          VerifyResult.unavailable);
    });

    test('unavailable when the vault has no ETH account', () async {
      setUpUnlocked();
      wallet.accountsValue = _accounts(const []);

      expect(await verifier.verifyMnemonic(_mnemonic),
          VerifyResult.unavailable);
    });

    test('unavailable when crypto returns a null seed', () async {
      setUpUnlocked();
      crypto.nullSeed = true;

      expect(await verifier.verifyMnemonic(_mnemonic),
          VerifyResult.unavailable);
    });

    test('unavailable when crypto returns a null address', () async {
      setUpUnlocked();
      crypto.nullAddress = true;

      expect(await verifier.verifyMnemonic(_mnemonic),
          VerifyResult.unavailable);
    });
  });

  group('verifyPassphrase', () {
    test('matches the correct passphrase', () async {
      setUpUnlocked(passphrase: 'correct');

      expect(await verifier.verifyPassphrase('correct'), VerifyResult.match);
    });

    test('mismatches a wrong passphrase', () async {
      setUpUnlocked(passphrase: 'correct');

      expect(await verifier.verifyPassphrase('wrong'), VerifyResult.mismatch);
    });

    test('unavailable while locked', () async {
      setUpUnlocked();
      wallet.mnemonicValue = null;

      expect(await verifier.verifyPassphrase('anything'),
          VerifyResult.unavailable);
    });

    test('unavailable when the vault has no ETH account', () async {
      setUpUnlocked();
      wallet.accountsValue = null;

      expect(await verifier.verifyPassphrase('anything'),
          VerifyResult.unavailable);
    });
  });

  group('verifyEnigma', () {
    setUp(() {
      crypto.enigmaPhrase = _phrase;
      wallet
        ..vault = _vault(source: VaultSource.enigma, enigmaLanguage: 1)
        ..mnemonicValue = _phrase
        ..accountsValue = _accounts([_ethAccount(_mnemonic, '')]);
    });

    test('matches a re-derived phrase word-by-word', () async {
      expect(await verifier.verifyEnigma('riddle', 'secret'),
          VerifyResult.match);
      // The persisted language and trimmed inputs reach the crypto layer.
      expect(crypto.enigmaCalls.single.language, 1);
      expect(crypto.enigmaCalls.single.riddle, 'riddle');
      expect(crypto.enigmaCalls.single.secret, 'secret');
    });

    test('trims riddle and secret before deriving', () async {
      await verifier.verifyEnigma('  my riddle  ', '  s3cret ');

      expect(crypto.enigmaCalls.single.riddle, 'my riddle');
      expect(crypto.enigmaCalls.single.secret, 's3cret');
    });

    test('mismatches a different phrase', () async {
      crypto.enigmaPhrase = _mnemonic;

      expect(await verifier.verifyEnigma('riddle', 'secret'),
          VerifyResult.mismatch);
    });

    test('mismatches a different word count', () async {
      crypto.enigmaPhrase = '$_phrase extra';

      expect(await verifier.verifyEnigma('riddle', 'secret'),
          VerifyResult.mismatch);
    });

    test('unavailable when crypto returns null', () async {
      crypto.enigmaPhrase = null;

      expect(await verifier.verifyEnigma('riddle', 'secret'),
          VerifyResult.unavailable);
    });

    test('unavailable while locked', () async {
      wallet.mnemonicValue = null;

      expect(await verifier.verifyEnigma('riddle', 'secret'),
          VerifyResult.unavailable);
    });
  });

  group('projections', () {
    test('isEnigma reflects the active vault source', () {
      wallet.vault = _vault(source: VaultSource.enigma);
      expect(verifier.isEnigma, isTrue);

      wallet.vault = _vault(source: VaultSource.imported);
      expect(verifier.isEnigma, isFalse);
    });

    test('hasPassphrase reflects the stored ciphertext', () {
      wallet.vault = _vault();
      expect(verifier.hasPassphrase, isFalse);

      wallet.vault = Vault(
        id: 'v1',
        label: '',
        depth: 0,
        mnemonicEncrypted: 'ciphertext',
        passphraseEncrypted: 'cipher-pass',
        accounts: _accounts(const []),
        createdAt: 0,
      );
      expect(verifier.hasPassphrase, isTrue);
    });

    test('projections are inert while locked', () {
      wallet.vault = null;
      expect(verifier.isEnigma, isFalse);
      expect(verifier.hasPassphrase, isFalse);
    });
  });
}
