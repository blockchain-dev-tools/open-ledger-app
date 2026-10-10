import 'dart:typed_data';

import '../core/interfaces/account_service.dart';
import '../core/interfaces/crypto_service.dart';
import '../core/models/chain.dart';
import '../core/models/wallet_accounts.dart';
import '../utils/fnv.dart';

/// Account derivation service — extracts account management from WalletService.
///
/// Implements [IAccountService] so [WalletService] depends on the interface,
/// not the concrete implementation.
///
/// Responsibilities:
/// - Derive default accounts for all 5 chains (ETH, SOL, BTC, TRX, SUI).
/// - Derive a single chain account from seed + path.
/// - Pure-data list operations (add/remove accounts from a [WalletAccounts]).
///
/// All cryptographic operations go through the injected [ICryptoService].
/// This service does NOT access storage or check wallet lock state —
/// those concerns belong to [WalletService].
class AccountService implements IAccountService {
  final ICryptoService _crypto;

  AccountService({required this._crypto});

  // ── Default derivation paths ──────────────────────────────────────────

  /// Account-0 paths for every chain, derived from the [Chain] registry so
  /// the UI can never disagree with what gets derived here.
  static final Map<String, String> _defaultPaths = Map.unmodifiable({
    for (final chain in Chain.values) chain.id: chain.defaultAccountPath,
  });

  @override
  Map<String, String> get defaultPaths => _defaultPaths;

  // ── Derive default accounts for all chains ────────────────────────────

  @override
  Future<WalletAccounts> deriveDefaultAccounts(
      String mnemonic, String passphrase, String seedHex) async {
    final accounts = <ChainAccount>[];
    for (final entry in defaultPaths.entries) {
      final account =
          await deriveSingleAccount(entry.key, entry.value, seedHex);
      if (account != null) {
        accounts.add(account);
      }
    }

    final fingerprint = fnv1aFingerprint(mnemonic);
    return WalletAccounts(
      accounts: accounts,
      mnemonicFingerprint: fingerprint,
    );
  }

  // ── Derive a single chain account ─────────────────────────────────────

  @override
  Future<ChainAccount?> deriveSingleAccount(
      String chain, String path, String seedHex) async {
    final address = _deriveAddress(chain, seedHex, path);
    if (address == null) return null;

    final privKey = _derivePrivateKey(chain, seedHex, path);
    if (privKey == null) return null;

    // The chain's *real* public key (ADR-011 §4). This field used to hold
    // `hex(privkey)` for ETH/BTC/Tron/Sui, which leaked the private key into
    // plaintext storage and made AccountDetail label a private key "公钥".
    final pubKeyBytes =
        _crypto.publicKeyForChain(chain, _crypto.hexEncode(privKey));

    return ChainAccount(
      chain: chain,
      address: address,
      derivationPath: path,
      publicKey: pubKeyBytes != null ? _crypto.hexEncode(pubKeyBytes) : '',
    );
  }

  /// Per-chain address derivation (each chain has its own scheme + path).
  String? _deriveAddress(String chain, String seedHex, String path) {
    switch (chain) {
      case 'ethereum':
        return _crypto.deriveEthAddress(seedHex, path);
      case 'solana':
        return _crypto.deriveSolAddress(seedHex, path);
      case 'bitcoin':
        return _crypto.deriveBtcAddress(seedHex, path);
      case 'tron':
        return _crypto.deriveTronAddress(seedHex, path);
      case 'sui':
        return _crypto.deriveSuiAddress(seedHex, path);
      default:
        return null;
    }
  }

  /// Ed25519 for Solana / Sui, secp256k1 for the rest.
  Uint8List? _derivePrivateKey(String chain, String seedHex, String path) {
    switch (chain) {
      case 'solana':
      case 'sui':
        return _crypto.deriveEd25519PrivateKey(seedHex, path);
      case 'ethereum':
      case 'bitcoin':
      case 'tron':
        return _crypto.deriveSecp256k1PrivateKey(seedHex, path);
      default:
        return null;
    }
  }

  // ── Pure-data list operations ─────────────────────────────────────────

  @override
  WalletAccounts addAccountToList(
      WalletAccounts accounts, ChainAccount account) {
    // Check for duplicates (same address + chain)
    final existing = accounts.accounts
        .where((a) => a.address == account.address && a.chain == account.chain);
    if (existing.isNotEmpty) return accounts;

    return accounts.copyWith(
      accounts: [...accounts.accounts, account],
    );
  }

  @override
  WalletAccounts removeAccountFromList(
      WalletAccounts accounts, String chain, String address) {
    return accounts.copyWith(
      accounts: accounts.accounts
          .where((a) => !(a.chain == chain && a.address == address))
          .toList(),
    );
  }

}
