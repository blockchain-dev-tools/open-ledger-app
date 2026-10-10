import '../models/wallet_accounts.dart';

/// Abstract interface for account management.
///
/// Implemented by [AccountService] in `lib/services/`.
/// [WalletService] depends on this interface, never on the concrete implementation.
abstract class IAccountService {
  /// Derive default accounts for all 5 chains (ETH, SOL, BTC, TRX, SUI).
  Future<WalletAccounts> deriveDefaultAccounts(
      String mnemonic, String passphrase, String seedHex);

  /// Derive a single [ChainAccount] for the given [chain] and derivation [path].
  Future<ChainAccount?> deriveSingleAccount(
      String chain, String path, String seedHex);

  /// Add a new account to the given [accounts] list.
  WalletAccounts addAccountToList(
      WalletAccounts accounts, ChainAccount account);

  /// Remove an account from the given [accounts] list.
  WalletAccounts removeAccountFromList(
      WalletAccounts accounts, String chain, String address);

  /// Default BIP derivation paths for all 5 chains.
  Map<String, String> get defaultPaths;
}
