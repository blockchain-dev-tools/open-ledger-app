/// Unit tests for [AccountService].
///
/// Covers derivation, default accounts, and pure-data list operations.
/// Uses a hand-written [ICryptoService] mock — no Rust .so required.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import '../support/inert_key_hierarchy.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/services/account_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Mock ICryptoService — configurable return values for each test scenario.
// ═══════════════════════════════════════════════════════════════════════

class _MockCryptoService with InertKeyHierarchy implements ICryptoService {
  /// Address returned by chain-specific derive methods.
  String? address;

  /// Private key bytes returned for secp256k1 derivation (ETH, BTC, TRX).
  Uint8List? secp256k1PrivKey;

  /// Private key bytes returned for Ed25519 derivation (SOL, SUI).
  Uint8List? ed25519PrivKey;

  /// Public key bytes returned by [solanaPublicKeyBytes].
  Uint8List? solPubKeyBytes;

  /// Public key bytes returned by [publicKeyForChain] (all chains).
  ///
  /// Deliberately distinct from the private keys above, so a test can prove
  /// the derived `publicKey` is the *public* key, not `hex(privkey)`
  /// (the bug ADR-011 §4 fixes).
  Uint8List? chainPubKeyBytes;

  _MockCryptoService({
    this.address,
    this.secp256k1PrivKey,
    this.ed25519PrivKey,
    this.solPubKeyBytes,
    this.chainPubKeyBytes,
  });

  // ── Address from Seed + Path ──────────────────────────────────────────

  @override
  String? deriveEthAddress(String seedHex, String path) => address;

  @override
  String? deriveSolAddress(String seedHex, String path) => address;

  @override
  String? deriveBtcAddress(String seedHex, String path) => address;

  @override
  String? deriveTronAddress(String seedHex, String path) => address;

  @override
  String? deriveSuiAddress(String seedHex, String path) => address;

  // ── HD Key Derivation ─────────────────────────────────────────────────

  @override
  Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) =>
      secp256k1PrivKey;

  @override
  Uint8List? deriveSecp256k1Extended(String seedHex, String path) => null;

  @override
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path) =>
      ed25519PrivKey;

  // ── Public Key ────────────────────────────────────────────────────────

  @override
  Uint8List? solanaPublicKeyBytes(String privkeyHex) => solPubKeyBytes;

  @override
  Uint8List? publicKeyForChain(String chain, String privkeyHex) =>
      chainPubKeyBytes;

  // Not exercised by AccountService.
  @override
  String? encodePrivateKey(String chain, String privkeyHex) => null;

  // ── Hex Utilities ─────────────────────────────────────────────────────

  @override
  String hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ── Stubs (unused by AccountService, required by interface) ──────────

  @override
  String generateMnemonic({int strength = 128}) =>
      throw UnimplementedError();

  @override
  bool validateMnemonic(String mnemonic) => throw UnimplementedError();

  @override
  String reencodeMnemonic(String mnemonic) => throw UnimplementedError();

  @override
  String? generateMnemonicLang(
          {int strength = 128, required int language}) =>
      throw UnimplementedError();

  @override
  bool validateMnemonicLang(String mnemonic, int language) =>
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
  String? pbkdf2Derive(String pin, String saltHex, int keyLen) =>
      throw UnimplementedError();

  @override
  String? mnemonicToSeed(String mnemonic, {String passphrase = ''}) =>
      throw UnimplementedError();

  @override
  String? chacha20Encrypt(
          String plaintext, String pin, String saltHex) =>
      throw UnimplementedError();

  @override
  String? chacha20Decrypt(
          String ciphertextHex, String pin, String saltHex) =>
      throw UnimplementedError();

  @override
  String? historyEncrypt(String plaintext, String seedHex) =>
      throw UnimplementedError();

  @override
  String? historyDecrypt(String cipherHex, String seedHex) =>
      throw UnimplementedError();

  @override
  bool constantTimeEquals(String a, String b) => a == b;

  @override
  Uint8List hexToBytes(String hex) => throw UnimplementedError();
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

const _testSeed = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
const _testPath = "m/44'/60'/0'/0/0";
const _testMnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

Uint8List _bytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  final result = Uint8List(clean.length ~/ 2);
  for (int i = 0; i < result.length; i++) {
    result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

WalletAccounts _wallet(List<ChainAccount> accounts) => WalletAccounts(
      accounts: accounts,
      mnemonicFingerprint: 'deadbeef',
    );

ChainAccount _account({
  String chain = 'ethereum',
  String address = '0x1234',
  String path = _testPath,
  String publicKey = 'ab01',
}) =>
    ChainAccount(
      chain: chain,
      address: address,
      derivationPath: path,
      publicKey: publicKey,
    );

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  // ── 1. defaultPaths ──────────────────────────────────────────────────

  test('defaultPaths returns 5 chain paths', () {
    final service = AccountService(crypto: _MockCryptoService());

    final paths = service.defaultPaths;

    expect(paths, hasLength(5));
    expect(paths.keys, containsAll([
      'ethereum',
      'solana',
      'bitcoin',
      'tron',
      'sui',
    ]));
  });

  // ── 2. deriveSingleAccount — ethereum ───────────────────────────────

  test('deriveSingleAccount returns ChainAccount for ethereum', () async {
    final privKey = _bytes('cafebabe');
    final mock = _MockCryptoService(
      address: '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B',
      secp256k1PrivKey: privKey,
      chainPubKeyBytes: _bytes('04a1b2c3'),
    );
    final service = AccountService(crypto: mock);

    final account =
        await service.deriveSingleAccount('ethereum', _testPath, _testSeed);

    expect(account, isNotNull);
    expect(account!.chain, 'ethereum');
    expect(account.address, '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B');
    expect(account.derivationPath, _testPath);
    expect(account.publicKey, '04a1b2c3');
    // Regression (ADR-011 §4): publicKey must NOT be hex(privkey).
    expect(account.publicKey, isNot('cafebabe'));
  });

  // ── 3. deriveSingleAccount returns null on crypto failure ────────────

  test('deriveSingleAccount returns null when crypto fails', () async {
    final mock = _MockCryptoService(address: null); // simulate failure
    final service = AccountService(crypto: mock);

    final account =
        await service.deriveSingleAccount('ethereum', _testPath, _testSeed);

    expect(account, isNull);
  });

  // ── 4. deriveSingleAccount — solana with public key ─────────────────

  test('deriveSingleAccount returns ChainAccount for solana with public key',
      () async {
    final edPriv = _bytes('deadbeef');
    final solPub = _bytes('baadf00d');
    final mock = _MockCryptoService(
      address: '7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV',
      ed25519PrivKey: edPriv,
      solPubKeyBytes: solPub,
      chainPubKeyBytes: solPub,
    );
    final service = AccountService(crypto: mock);

    final account = await service.deriveSingleAccount(
        'solana', "m/44'/501'/0'/0'", _testSeed);

    expect(account, isNotNull);
    expect(account!.chain, 'solana');
    expect(account.address, '7EcDhSYGxXyscszYEp35KHN8vvw3svAuLKTzXwCFLtV');
    expect(account.publicKey, 'baadf00d');
  });

  // ── 5. deriveDefaultAccounts ────────────────────────────────────────

  test('deriveDefaultAccounts returns WalletAccounts with 5 accounts',
      () async {
    final privKey = _bytes('cafebabe');
    final edPriv = _bytes('deadbeef');
    final solPub = _bytes('baadf00d');
    final mock = _MockCryptoService(
      address: '0xTest1234',
      secp256k1PrivKey: privKey,
      ed25519PrivKey: edPriv,
      solPubKeyBytes: solPub,
    );
    final service = AccountService(crypto: mock);

    final wallet = await service.deriveDefaultAccounts(
        _testMnemonic, '', _testSeed);

    expect(wallet.accounts, hasLength(5));
    expect(wallet.mnemonicFingerprint, isNotEmpty);
    expect(wallet.mnemonicFingerprint, hasLength(8));

    final chains = wallet.accounts.map((a) => a.chain).toSet();
    expect(chains, containsAll([
      'ethereum',
      'solana',
      'bitcoin',
      'tron',
      'sui',
    ]));
  });

  // ── 6. addAccountToList — appends ────────────────────────────────────

  test('addAccountToList appends new account', () {
    final service = AccountService(crypto: _MockCryptoService());
    final existing = _wallet([_account(address: '0xAAA')]);
    final newAccount = _account(address: '0xBBB');

    final result = service.addAccountToList(existing, newAccount);

    expect(result.accounts, hasLength(2));
    expect(result.accounts.last.address, '0xBBB');
  });

  // ── 7. addAccountToList — no duplicate ──────────────────────────────

  test('addAccountToList does not append duplicate (same address + chain)',
      () {
    final service = AccountService(crypto: _MockCryptoService());
    final account = _account(address: '0xAAA', chain: 'ethereum');
    final wallet = _wallet([account]);
    final duplicate = _account(address: '0xAAA', chain: 'ethereum');

    final result = service.addAccountToList(wallet, duplicate);

    expect(result.accounts, hasLength(1));
  });

  test(
      'addAccountToList appends account with same address but different chain',
      () {
    final service = AccountService(crypto: _MockCryptoService());
    final eth = _account(address: '0xAAA', chain: 'ethereum');
    final sol = _account(address: '0xAAA', chain: 'solana');
    final wallet = _wallet([eth]);

    final result = service.addAccountToList(wallet, sol);

    expect(result.accounts, hasLength(2));
  });

  // ── 8. removeAccountFromList — removes match ─────────────────────────

  test('removeAccountFromList removes matching account', () {
    final service = AccountService(crypto: _MockCryptoService());
    final eth = _account(address: '0xAAA', chain: 'ethereum');
    final btc = _account(address: '0xBBB', chain: 'bitcoin');
    final wallet = _wallet([eth, btc]);

    final result = service.removeAccountFromList(wallet, 'ethereum', '0xAAA');

    expect(result.accounts, hasLength(1));
    expect(result.accounts.single.chain, 'bitcoin');
  });

  // ── 9. removeAccountFromList — no match ──────────────────────────────

  test('removeAccountFromList returns unchanged when no match', () {
    final service = AccountService(crypto: _MockCryptoService());
    final eth = _account(address: '0xAAA', chain: 'ethereum');
    final wallet = _wallet([eth]);

    final result =
        service.removeAccountFromList(wallet, 'solana', '0xNOTFOUND');

    expect(result.accounts, hasLength(1));
    expect(result.accounts.single, eth);
  });

  // ── 10. Iterate all 5 chains through deriveSingleAccount ─────────────

  group('deriveSingleAccount — all 5 chains', () {
    late AccountService service;
    final secpPriv = _bytes('cafebabe');
    final edPriv = _bytes('deadbeef');
    final solPub = _bytes('baadf00d');
    final chainPub = _bytes('02feedface');

    setUp(() {
      service = AccountService(
        crypto: _MockCryptoService(
          address: '0xAllChains',
          secp256k1PrivKey: secpPriv,
          ed25519PrivKey: edPriv,
          solPubKeyBytes: solPub,
          chainPubKeyBytes: chainPub,
        ),
      );
    });

    test('ethereum', () async {
      final account =
          await service.deriveSingleAccount('ethereum', _testPath, _testSeed);
      expect(account, isNotNull);
      expect(account!.chain, 'ethereum');
      expect(account.address, '0xAllChains');
      expect(account.publicKey, '02feedface');
    });

    test('solana', () async {
      final account = await service.deriveSingleAccount(
          'solana', "m/44'/501'/0'/0'", _testSeed);
      expect(account, isNotNull);
      expect(account!.chain, 'solana');
      expect(account.publicKey, '02feedface');
    });

    test('bitcoin', () async {
      final account =
          await service.deriveSingleAccount('bitcoin', _testPath, _testSeed);
      expect(account, isNotNull);
      expect(account!.chain, 'bitcoin');
      expect(account.publicKey, '02feedface');
    });

    test('tron', () async {
      final account =
          await service.deriveSingleAccount('tron', _testPath, _testSeed);
      expect(account, isNotNull);
      expect(account!.chain, 'tron');
      expect(account.publicKey, '02feedface');
    });

    test('sui', () async {
      final account =
          await service.deriveSingleAccount('sui', _testPath, _testSeed);
      expect(account, isNotNull);
      expect(account!.chain, 'sui');
      expect(account.publicKey, '02feedface');
    });
  });
}
