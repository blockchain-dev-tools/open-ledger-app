import 'dart:typed_data';

import '../core/interfaces/account_service.dart';
import '../core/interfaces/chain_host_service.dart';
import '../core/interfaces/crypto_service.dart';
import '../core/models/bitcoin_address_type.dart';
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

  /// Rust chain-app host (stage 4). When present, derivation goes through
  /// `LocalCommand::DeriveAccount`, so the seed never crosses FFI per call.
  /// Any failure falls back to [ICryptoService] — the migration stays
  /// reversible per chain.
  final IChainHostService? _chainHost;

  AccountService({required this._crypto, this._chainHost});

  /// Chain id → Rust module id.
  static const Map<String, String> _moduleIds = {
    'ethereum': 'openledger.ethereum',
    'solana': 'openledger.solana',
    'bitcoin': 'openledger.bitcoin',
    'tron': 'openledger.tron',
    'sui': 'openledger.sui',
    'near': 'openledger.near',
    'ton': 'openledger.ton',
  };

  // ── Default derivation paths ──────────────────────────────────────────

  /// Account-0 paths for the chains a new vault shows by default, derived
  /// from the [Chain] registry so the UI can never disagree with what gets
  /// derived here.
  static final Map<String, String> _defaultPaths = Map.unmodifiable({
    for (final chain in Chain.defaultVisible)
      chain.id: chain.defaultAccountPath,
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
    final fromHost = _deriveViaHost(chain, path, seedHex);
    if (fromHost != null) return fromHost;

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

  /// Stage 4：本机账户统一入口。只在「路径是该链的标准账户模板」时走 Rust
  /// 模块，保证任意自定义路径仍由旧实现处理。
  ///
  /// Bitcoin 有四种地址类型，每种都是模板 `m/{44,49,84,86}'/0'/0'/0/{index}`；
  /// 类型由路径决定，并作为 `accountProfileIndex` 传给模块。
  ChainAccount? _deriveViaHost(String chain, String path, String seedHex) {
    final host = _chainHost;
    if (host == null || !host.isAvailable) return null;
    final moduleId = _moduleIds[chain];
    if (moduleId == null) return null;

    Chain? model;
    for (final candidate in Chain.values) {
      if (candidate.id == chain) {
        model = candidate;
        break;
      }
    }
    if (model == null) return null;
    final index = model.accountIndexFromPath(path);

    var profileIndex = 0;
    if (model == Chain.bitcoin) {
      final type = BitcoinAddressType.fromPath(path);
      if (type == null || type.pathForIndex(index) != path) return null;
      profileIndex = type.profileIndex;
    } else if (model.accountPathForIndex(index) != path) {
      return null;
    }

    host.setSeed(seedHex);
    final material = host.deriveAccount(
      moduleId,
      accountProfileIndex: profileIndex,
      addressIndex: index,
    );
    if (material == null) return null;
    return ChainAccount(
      chain: chain,
      address: material.address,
      derivationPath: path,
      publicKey: material.publicKeyHex,
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
      case 'near':
        return _crypto.deriveNearAddress(seedHex, path);
      case 'ton':
        return _crypto.deriveTonAddress(seedHex, path);
      default:
        return null;
    }
  }

  /// Ed25519 for Solana / Sui / NEAR / TON, secp256k1 for the rest.
  Uint8List? _derivePrivateKey(String chain, String seedHex, String path) {
    switch (chain) {
      case 'solana':
      case 'sui':
      case 'near':
      case 'ton':
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
