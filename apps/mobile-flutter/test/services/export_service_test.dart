/// Unit tests for [ExportService] (ADR-011).
///
/// The service is a thin composition: pick the derivation path for a chain,
/// then hand the bytes to the Rust-backed encoder. These tests pin that
/// dispatch down — the actual encoding vectors (WIF / base58 / bech32) live
/// beside the Rust implementation in `crates/open-ledger-biz/src/export.rs`.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/crypto_service.dart';
import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/services/export_service.dart';

/// Records every derivation / encoding call so the dispatch is observable.
class _RecordingCrypto implements ICryptoService {
  final List<({String path, bool ed25519})> derives = [];
  final List<({String chain, String hex})> encodes = [];

  @override
  Uint8List? deriveSecp256k1PrivateKey(String seedHex, String path) {
    derives.add((path: path, ed25519: false));
    return Uint8List.fromList(List<int>.filled(32, 0x11));
  }

  @override
  Uint8List? deriveEd25519PrivateKey(String seedHex, String path) {
    derives.add((path: path, ed25519: true));
    return Uint8List.fromList(List<int>.filled(32, 0x22));
  }

  @override
  String? encodePrivateKey(String chain, String privkeyHex) {
    encodes.add((chain: chain, hex: privkeyHex));
    return '$chain:$privkeyHex';
  }

  @override
  String hexEncode(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Minimal wallet view: only the members [ExportService] reads.
class _FakeWallet implements IWalletService {
  _FakeWallet({this.seedHexValue});

  String? seedHexValue;
  WalletAccounts? accountsValue;
  String? passphraseEncrypted;
  String? mnemonicValue;
  String sessionPin = '123456';

  @override
  String? get seedHex => seedHexValue;

  @override
  String? get passphrase => null;

  @override
  WalletAccounts? getAccounts() => accountsValue;

  @override
  Vault? get activeVault => Vault(
        id: 'v1',
        label: '',
        depth: 0,
        mnemonicEncrypted: 'ciphertext',
        passphraseEncrypted: passphraseEncrypted,
        accounts: accountsValue ??
            const WalletAccounts(accounts: [], mnemonicFingerprint: ''),
        createdAt: 0,
      );

  @override
  Future<bool> verifySessionPin(String pin) async => pin == sessionPin;

  @override
  Future<String?> revealMnemonic(String pin) async =>
      pin == sessionPin ? mnemonicValue : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

const _ethAccount = ChainAccount(
  address: '0xabc',
  derivationPath: "m/44'/60'/0'/0/0",
  publicKey: '04aa',
  chain: 'ethereum',
);

const _btcAccount = ChainAccount(
  address: 'bc1q...',
  derivationPath: "m/84'/0'/0'/0/0",
  publicKey: '02bb',
  chain: 'bitcoin',
);

const _tronAccount = ChainAccount(
  address: 'T...',
  derivationPath: "m/44'/195'/0'/0/0",
  publicKey: '04cc',
  chain: 'tron',
);

const _solAccount = ChainAccount(
  address: 'So1...',
  derivationPath: "m/44'/501'/0'/0'",
  publicKey: 'dd',
  chain: 'solana',
);

const _suiAccount = ChainAccount(
  address: '0xsu',
  derivationPath: "m/44'/784'/0'/0'/0'",
  publicKey: 'ee',
  chain: 'sui',
);

const _seedHex = 'deadbeef';

void main() {
  late _RecordingCrypto crypto;
  late _FakeWallet wallet;
  late ExportService service;

  setUp(() {
    crypto = _RecordingCrypto();
    wallet = _FakeWallet(seedHexValue: _seedHex);
    service = ExportService(wallet: wallet, crypto: crypto);
  });

  group('encodePrivateKey — chain dispatch', () {
    test('secp256k1 chains derive via the secp path', () async {
      for (final account in [_ethAccount, _btcAccount, _tronAccount]) {
        service.encodePrivateKey(account);

        expect(crypto.derives.last.ed25519, isFalse,
            reason: '${account.chain} must use secp256k1');
        expect(crypto.derives.last.path, account.derivationPath);
        expect(crypto.encodes.last.chain, account.chain);
      }
    });

    test('Ed25519 chains derive via the SLIP-10 path', () async {
      for (final account in [_solAccount, _suiAccount]) {
        service.encodePrivateKey(account);

        expect(crypto.derives.last.ed25519, isTrue,
            reason: '${account.chain} must use Ed25519');
        expect(crypto.derives.last.path, account.derivationPath);
        expect(crypto.encodes.last.chain, account.chain);
      }
    });

    test('the derived key is hex-encoded before encoding', () {
      final encoded = service.encodePrivateKey(_ethAccount);

      // 32 bytes of 0x11 → 64 hex chars, forwarded verbatim to the encoder.
      expect(encoded, 'ethereum:${'11' * 32}');
    });

    test('returns null and derives nothing while locked', () {
      wallet.seedHexValue = null;

      expect(service.encodePrivateKey(_ethAccount), isNull);
      expect(crypto.derives, isEmpty);
      expect(crypto.encodes, isEmpty);
    });

    test('returns null for an unknown chain', () {
      const unknown = ChainAccount(
        address: 'x',
        derivationPath: "m/0",
        publicKey: '',
        chain: 'dogecoin',
      );

      expect(service.encodePrivateKey(unknown), isNull);
      expect(crypto.derives, isEmpty);
    });
  });

  group('encodingLabel', () {
    test('names the importable encoding per chain', () {
      expect(service.encodingLabel(_ethAccount), '0x + 32B hex');
      expect(service.encodingLabel(_btcAccount), 'WIF (mainnet, compressed)');
      expect(service.encodingLabel(_solAccount), 'base58 (64B keypair)');
      expect(service.encodingLabel(_suiAccount), 'bech32 suiprivkey');
    });

    test('is null for an unknown chain', () {
      const unknown = ChainAccount(
        address: 'x',
        derivationPath: "m/0",
        publicKey: '',
        chain: 'dogecoin',
      );
      expect(service.encodingLabel(unknown), isNull);
    });
  });

  group('wallet projection', () {
    test('hasPassphrase reflects the active vault ciphertext', () {
      expect(service.hasPassphrase, isFalse);
      wallet.passphraseEncrypted = 'cipher';
      expect(service.hasPassphrase, isTrue);
    });

    test('fingerprint / accounts come from the active vault', () {
      wallet.accountsValue = const WalletAccounts(
        accounts: [_ethAccount],
        mnemonicFingerprint: 'c0ffee12',
      );

      expect(service.fingerprint, 'c0ffee12');
      expect(service.accounts, const [_ethAccount]);
    });

    test('accounts is empty while locked', () {
      wallet.accountsValue = null;
      expect(service.accounts, isEmpty);
      expect(service.fingerprint, isNull);
    });
  });

  group('PIN gate forwarding', () {
    test('verifySessionPin forwards to the wallet session', () async {
      wallet.sessionPin = '654321';

      expect(await service.verifySessionPin('654321'), isTrue);
      expect(await service.verifySessionPin('123456'), isFalse);
    });

    test('revealMnemonic returns null on a non-session PIN', () async {
      wallet.sessionPin = '654321';
      wallet.mnemonicValue = 'abandon ability able';

      expect(await service.revealMnemonic('654321'), 'abandon ability able');
      expect(await service.revealMnemonic('123456'), isNull);
    });
  });
}
