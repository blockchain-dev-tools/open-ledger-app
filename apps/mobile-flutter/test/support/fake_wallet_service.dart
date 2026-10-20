/// Configurable [IWalletService] fake for widget tests.
///
/// No storage, no crypto, no FFI. Records stand-in mutation calls so tests can
/// assert the exact credential arguments the UI passed.
library;

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';

class FakeWalletService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  FakeWalletService({
    this.isStandInSession = false,
    bool standInConfigured = false,
    StandInMode standInMode = StandInMode.hide,
  }) {
    _standInConfigured = standInConfigured;
    _standInMode = standInMode;
  }

  @override
  final bool isStandInSession;

  bool _standInConfigured = false;
  StandInMode _standInMode = StandInMode.hide;
  bool _unlocked = true;

  final List<({String mnemonic, String pin, String mainPin, StandInMode mode})>
      configureCalls = [];
  final List<({String oldPin, String newPin})> updatePinCalls = [];
  final List<({String pin, StandInMode mode})> updateModeCalls = [];
  final List<String> removePins = [];

  @override
  Future<bool> hasWallet() async => true;

  @override
  Future<bool> isLocked() async => false;

  @override
  bool get isUnlocked => _unlocked;

  @override
  void lock() => _unlocked = false;

  @override
  Future<bool> verifyPin(String pin) async => true;

  @override
  int get pinAttempts => 0;

  @override
  int get maxPinAttempts => 5;

  @override
  int? get sessionDepth => isStandInSession ? 1 : 0;

  @override
  List<Vault> get vaults => const [];

  @override
  String? get activeVaultId => null;

  @override
  Vault? get activeVault => null;

  @override
  Future<bool> hasStandIn() async => _standInConfigured;

  @override
  Future<StandInMode> standInMode() async => _standInMode;

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
    configureCalls
        .add((mnemonic: mnemonic, pin: pin, mainPin: mainPin, mode: mode));
    _standInConfigured = true;
    _standInMode = mode;
  }

  @override
  Future<void> updateStandInPin({
    required String oldPin,
    required String newPin,
  }) async {
    updatePinCalls.add((oldPin: oldPin, newPin: newPin));
  }

  @override
  Future<void> updateStandInMode({
    required String pin,
    required StandInMode mode,
  }) async {
    updateModeCalls.add((pin: pin, mode: mode));
    _standInMode = mode;
  }

  @override
  Future<void> removeStandIn({required String pin}) async {
    removePins.add(pin);
    _standInConfigured = false;
    _standInMode = StandInMode.hide;
  }

  @override
  Future<void> switchVault(String id) async {}

  @override
  Future<void> renameVault(String id, String label) async {}

  @override
  Future<WalletAccounts> setupWallet(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async =>
      throw UnimplementedError();

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
      throw UnimplementedError();

  @override
  Future<void> removeVault(String id, {required String pin}) async {}

  @override
  Future<WalletAccounts> unlockWallet(String pin) async =>
      throw UnimplementedError();

  @override
  Future<void> clearWallet() async {}

  @override
  Future<void> resetAll() async {}

  @override
  WalletAccounts? getAccounts() => null;

  @override
  Future<WalletAccounts> addAccount(String chain, String path) async =>
      throw UnimplementedError();

  @override
  Future<WalletAccounts> removeAccount(String chain, String address) async =>
      throw UnimplementedError();

  @override
  Future<String?> revealMnemonic(String pin) async => null;

  @override
  String? get seedHex => null;

  @override
  String? get mnemonic => null;

  @override
  String? get passphrase => null;

  @override
  Future<bool> updatePin(String oldPin, String newPin) async => true;
}
