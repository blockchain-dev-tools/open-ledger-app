import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';

import 'sample_accounts.dart';

/// Gallery fake for [IWalletService] (ADR-005).
///
/// Returns a fixed, populated wallet so the Accounts tab renders its real
/// list state (fingerprint banner, chain sections, address rows) instead of
/// the empty state. No storage, no crypto, no FFI — the gallery must stay
/// web-compatible.
///
/// Mutating methods are inert except for the stand-in wallet, whose state is
/// tracked so the gallery can preview (and drive) the setup wizard and the
/// configured status view.
class FakeWalletService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  FakeWalletService({
    this.isStandInSession = false,
    this.lockedOut = false,
    bool standInConfigured = false,
    StandInMode standInMode = StandInMode.hide,
  }) {
    _standInConfigured = standInConfigured;
    _standInMode = standInMode;
  }

  /// Gallery-only: previews the permanent lockout view (5 exhausted attempts)
  /// instead of the PIN pad. No storage, no counter — purely a UI state.
  final bool lockedOut;

  final WalletAccounts _accounts = sampleWalletAccounts;
  bool _unlocked = true;

  /// Stand-in state — configurable so the gallery can preview both the
  /// "not configured" wizard and the configured status view.
  bool _standInConfigured = false;
  StandInMode _standInMode = StandInMode.hide;

  @override
  final bool isStandInSession;

  @override
  Future<bool> hasWallet() async => true;

  @override
  Future<bool> isLocked() async => lockedOut;

  @override
  bool get isUnlocked => _unlocked;

  @override
  void lock() => _unlocked = false;

  @override
  Future<bool> verifyPin(String pin) async => true;

  @override
  int get pinAttempts => lockedOut ? maxPinAttempts : 0;

  @override
  int get maxPinAttempts => 5;

  @override
  Future<WalletAccounts> setupWallet(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async =>
      _accounts;

  @override
  Future<WalletAccounts> unlockWallet(String pin) async => _accounts;

  @override
  Future<void> clearWallet() async {}

  @override
  WalletAccounts? getAccounts() => _accounts;

  @override
  Future<WalletAccounts> addAccount(String chain, String path) async =>
      _accounts;

  @override
  Future<WalletAccounts> removeAccount(String chain, String address) async =>
      _accounts;

  final Set<String> _hidden = {};

  @override
  Set<String> get hiddenChains => _hidden;

  @override
  Future<void> setChainHidden(String chain, {required bool hidden}) async {
    hidden ? _hidden.add(chain) : _hidden.remove(chain);
  }

  @override
  Future<String?> revealMnemonic(String pin) async => null;

  @override
  String? get seedHex => null;

  @override
  String? get mnemonic => null;

  /// Models an unlocked vault with no passphrase.
  @override
  String? get passphrase => '';

  @override
  Future<bool> updatePin(String oldPin, String newPin) async => true;

  // ── Multi-vault session (single fixed vault for previews) ───────────

  Vault get _vault => Vault(
        id: 'gallery-vault',
        label: '',
        depth: 0,
        mnemonicEncrypted: 'gallery-encrypted-mnemonic',
        accounts: _accounts,
        createdAt: 0,
      );

  @override
  List<Vault> get vaults => _unlocked ? [_vault] : const [];

  @override
  String? get activeVaultId => _unlocked ? _vault.id : null;

  @override
  Vault? get activeVault => _unlocked ? _vault : null;

  @override
  int? get sessionDepth => _unlocked ? (isStandInSession ? 1 : 0) : null;

  /// Session-relative (matches the real service): reports whether the current
  /// session's child tier (`depth + 1`) is configured. The fake stores a single
  /// flag, so a stand-in preview with [standInConfigured] `false` shows the
  /// settings row as "Not set up".
  @override
  Future<bool> hasStandIn() async => _standInConfigured;

  @override
  Future<StandInMode> standInMode() async => _standInMode;

  // ── Stand-in management (stateful so gallery previews can toggle) ───

  @override
  bool get lastUnlockWiped => false;

  @override
  Future<void> configureStandIn(
    String mnemonic, {
    required String pin,
    required String mainPin,
    StandInMode mode = StandInMode.hide,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async {
    _standInConfigured = true;
    _standInMode = mode;
  }

  @override
  Future<void> updateStandInPin({
    required String oldPin,
    required String newPin,
  }) async {}

  @override
  Future<void> updateStandInMode({
    required String pin,
    required StandInMode mode,
  }) async {
    _standInMode = mode;
  }

  @override
  Future<void> removeStandIn({required String pin}) async {
    _standInConfigured = false;
    _standInMode = StandInMode.hide;
  }

  @override
  Future<void> resetAll() async {}

  @override
  Future<void> switchVault(String id) async {}

  @override
  Future<void> renameVault(String id, String label) async {}

  @override
  Future<WalletAccounts> addVault(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    String label = '',
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async =>
      _accounts;

  @override
  Future<void> removeVault(String id, {required String pin}) async {}
}
