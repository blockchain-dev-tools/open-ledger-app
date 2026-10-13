/// Wallet account types mirroring open-ledger-mono's address derivation.
///
/// Includes 5 chains: Ethereum, Solana, Bitcoin, Tron, Sui.
library;

import 'chain.dart';

/// A single chain account derived from the wallet's mnemonic.
class ChainAccount {
  /// On-chain address (hex for ETH, base58 for Solana, bech32 for BTC, etc.)
  final String address;

  /// BIP-32 / SLIP-10 derivation path (e.g. "m/44'/60'/0'/0/0")
  final String derivationPath;

  /// Public key bytes encoded as hex string.
  final String publicKey;

  /// Chain identifier: 'ethereum', 'solana', 'bitcoin', 'tron', or 'sui'.
  final String chain;

  /// The account number this account represents on [chain] — e.g. `0` for the
  /// default ETH path `m/44'/60'/0'/0/0`, or `1` for Solana's second account
  /// `m/44'/501'/1'/0'`.
  int get accountIndex =>
      Chain.fromId(chain)?.accountIndexFromPath(derivationPath) ?? 0;

  const ChainAccount({
    required this.address,
    required this.derivationPath,
    required this.publicKey,
    required this.chain,
  });

  /// Deserialize from a JSON map.
  factory ChainAccount.fromJson(Map<String, dynamic> json) {
    return ChainAccount(
      address: json['address'] as String,
      derivationPath: json['derivationPath'] as String,
      publicKey: json['publicKey'] as String,
      chain: json['chain'] as String,
    );
  }

  /// Serialize to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'derivationPath': derivationPath,
      'publicKey': publicKey,
      'chain': chain,
    };
  }

  /// Create a copy with optional field overrides.
  ChainAccount copyWith({
    String? address,
    String? derivationPath,
    String? publicKey,
    String? chain,
  }) {
    return ChainAccount(
      address: address ?? this.address,
      derivationPath: derivationPath ?? this.derivationPath,
      publicKey: publicKey ?? this.publicKey,
      chain: chain ?? this.chain,
    );
  }

  @override
  String toString() =>
      'ChainAccount(chain: $chain, path: $derivationPath, address: $address)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChainAccount &&
          address == other.address &&
          derivationPath == other.derivationPath &&
          publicKey == other.publicKey &&
          chain == other.chain;

  @override
  int get hashCode => Object.hash(address, derivationPath, publicKey, chain);
}

/// All chain accounts derived from a wallet mnemonic.
class WalletAccounts {
  /// Derived accounts across all enabled chains.
  final List<ChainAccount> accounts;

  /// 8-hex-character FNV-1a fingerprint of the mnemonic
  /// (see `utils/fnv.dart`). Identifies a wallet for display and equality
  /// checks without storing the mnemonic itself.
  ///
  /// **Not a cryptographic hash**: 32 bits, trivially collidable — never use it
  /// as a security boundary. It also covers the mnemonic *only*, so the same
  /// mnemonic with a different passphrase yields the same value; it therefore
  /// cannot decide whether two vaults are the same wallet.
  final String mnemonicFingerprint;

  const WalletAccounts({
    required this.accounts,
    required this.mnemonicFingerprint,
  });

  /// Deserialize from a JSON map.
  factory WalletAccounts.fromJson(Map<String, dynamic> json) {
    return WalletAccounts(
      accounts: (json['accounts'] as List<dynamic>)
          .map((a) =>
              ChainAccount.fromJson(a as Map<String, dynamic>))
          .toList(),
      mnemonicFingerprint: json['mnemonicFingerprint'] as String,
    );
  }

  /// Serialize to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'accounts': accounts.map((a) => a.toJson()).toList(),
      'mnemonicFingerprint': mnemonicFingerprint,
    };
  }

  /// Create a copy with optional field overrides.
  WalletAccounts copyWith({
    List<ChainAccount>? accounts,
    String? mnemonicFingerprint,
  }) {
    return WalletAccounts(
      accounts: accounts ?? this.accounts,
      mnemonicFingerprint: mnemonicFingerprint ?? this.mnemonicFingerprint,
    );
  }

  @override
  String toString() =>
      'WalletAccounts(accounts: ${accounts.length}, fingerprint: $mnemonicFingerprint)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletAccounts &&
          _listEquals(accounts, other.accounts) &&
          mnemonicFingerprint == other.mnemonicFingerprint;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(accounts), mnemonicFingerprint);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
