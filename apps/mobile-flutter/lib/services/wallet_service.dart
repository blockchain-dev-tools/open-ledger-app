import '../biz/wallet_biz.dart';
import '../core/interfaces/account_service.dart';
import '../core/interfaces/mnemonic_service.dart';
import '../core/interfaces/pin_auth_service.dart';
import '../core/interfaces/vault_repository.dart';
import '../core/interfaces/wallet_service.dart';
import '../core/models/vault.dart';
import '../core/models/wallet_accounts.dart';

/// Wallet lifecycle orchestration service.
///
/// Thin delegate over [WalletBiz], plus direct PIN management (existence
/// checks, attempt/lockout queries). The multi-vault session state
/// (`_vaults`, `_activeVaultId`, decrypted secrets) lives in [WalletBiz].
class WalletService implements IWalletService {
  final IPinAuthService _pinAuth;
  final WalletBiz _biz;

  WalletService({
    required IPinAuthService pinAuth,
    required IAccountService accountService,
    required IMnemonicService mnemonicService,
    required IVaultRepository repo,
  })  : _pinAuth = pinAuth,
        _biz = WalletBiz(
          pinAuth: pinAuth,
          accountService: accountService,
          mnemonicService: mnemonicService,
          repo: repo,
        );

  // ── Wallet existence / lock ────────────────────────────────────────

  @override
  Future<bool> hasWallet() => _biz.hasWallet();

  @override
  Future<bool> isLocked() => _pinAuth.isLocked();

  @override
  int get pinAttempts => _pinAuth.pinAttempts;

  /// Max allowed PIN attempts.
  int get maxPinAttempts => _pinAuth.maxPinAttempts;

  @override
  bool get isUnlocked => _biz.isUnlocked;

  @override
  String? get mnemonic => _biz.mnemonic;

  /// The active vault's cached passphrase (empty string if none).
  @override
  String? get passphrase => _biz.passphrase;

  @override
  String? get seedHex => _biz.seedHex;

  // ── Session (multi-vault) ──────────────────────────────────────────

  @override
  List<Vault> get vaults => _biz.vaults;

  @override
  String? get activeVaultId => _biz.activeVaultId;

  @override
  Vault? get activeVault => _biz.activeVault;

  @override
  int? get sessionDepth => _biz.sessionDepth;

  @override
  bool get isStandInSession => _biz.isStandInSession;

  @override
  Future<bool> hasStandIn() => _biz.hasStandIn();

  @override
  Future<StandInMode> standInMode() => _biz.standInMode();

  @override
  bool get lastUnlockWiped => _biz.lastUnlockWiped;

  @override
  Future<void> configureStandIn(
    String mnemonic, {
    required String pin,
    required String mainPin,
    StandInMode mode = StandInMode.hide,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) =>
      _biz.configureStandIn(mnemonic,
          pin: pin,
          mainPin: mainPin,
          mode: mode,
          source: source,
          enigmaLanguage: enigmaLanguage);

  @override
  Future<void> updateStandInPin({
    required String oldPin,
    required String newPin,
  }) =>
      _biz.updateStandInPin(oldPin: oldPin, newPin: newPin);

  @override
  Future<void> updateStandInMode({
    required String pin,
    required StandInMode mode,
  }) =>
      _biz.updateStandInMode(pin: pin, mode: mode);

  @override
  Future<void> removeStandIn({required String pin}) =>
      _biz.removeStandIn(pin: pin);

  @override
  Future<void> switchVault(String id) => _biz.switchVault(id);

  @override
  Future<void> renameVault(String id, String label) =>
      _biz.renameVault(id, label);

  // ── Wallet lifecycle ───────────────────────────────────────────────

  @override
  Future<WalletAccounts> setupWallet(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) =>
      _biz.setupWallet(mnemonic,
          pin: pin,
          passphrase: passphrase,
          storePassphrase: storePassphrase,
          source: source,
          enigmaLanguage: enigmaLanguage);

  @override
  Future<WalletAccounts> addVault(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    String label = '',
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) =>
      _biz.addVault(mnemonic,
          pin: pin,
          passphrase: passphrase,
          storePassphrase: storePassphrase,
          label: label,
          source: source,
          enigmaLanguage: enigmaLanguage);

  @override
  Future<void> removeVault(String id, {required String pin}) =>
      _biz.removeVault(id, pin: pin);

  @override
  Future<WalletAccounts> unlockWallet(String pin) => _biz.unlockWallet(pin);

  /// Verify a PIN **without** decrypting any vault (accepts any tier).
  @override
  Future<bool> verifyPin(String pin) => _pinAuth.verifyPin(pin);

  /// Verify a PIN against the **current session's** tier only.
  @override
  Future<bool> verifySessionPin(String pin) => _biz.verifySessionPin(pin);

  @override
  set onActiveVaultChanged(void Function()? callback) =>
      _biz.onActiveVaultChanged = callback;

  @override
  set onVaultsDestroyed(void Function(Set<String> vaultIds)? callback) =>
      _biz.onVaultsDestroyed = callback;

  @override
  WalletAccounts? getAccounts() => _biz.accounts;

  @override
  Future<WalletAccounts> addAccount(String chain, String path) =>
      _biz.addAccount(chain, path);

  @override
  Future<WalletAccounts> removeAccount(String chain, String address) =>
      _biz.removeAccount(chain, address);

  @override
  Future<String?> revealMnemonic(String pin) => _biz.revealMnemonic(pin);

  @override
  Future<void> clearWallet() => _biz.clearWallet();

  @override
  Future<void> resetAll() => _biz.resetAll();

  @override
  Future<bool> updatePin(String oldPin, String newPin) =>
      _biz.updatePin(oldPin, newPin);

  // ── PIN attempt management ────────────────────────────────────────

  int getPinAttempts() => _pinAuth.pinAttempts;

  Future<void> incrementPinAttempts() => _pinAuth.incrementPinAttempts();

  Future<void> resetPinAttempts() => _pinAuth.resetPinAttempts();

  // ── Lock ───────────────────────────────────────────────────────────

  @override
  void lock() => _biz.lock();
}
