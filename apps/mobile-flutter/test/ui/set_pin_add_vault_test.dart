// Widget tests for the [SetPinScreen] `addVault` single-phase branch.
//
// Covers:
// - entering 6 digits calls `walletService.addVault(mnemonic, pin: ...)`
//   and navigates home on success
// - a StateError (wrong session PIN) surfaces a localized error and does
//   not navigate

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/set_pin/set_pin_screen.dart';

class _FakeWalletService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  _FakeWalletService({this.addVaultError});

  final String? addVaultError;
  String? addedMnemonic;
  String? addedPin;

  @override
  Future<WalletAccounts> addVault(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    String label = '',
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async {
    if (addVaultError != null) throw StateError(addVaultError!);
    addedMnemonic = mnemonic;
    addedPin = pin;
    return const WalletAccounts(mnemonicFingerprint: 'x', accounts: []);
  }

  // ── Unused stubs ────────────────────────────────────────────────────

  @override
  Future<bool> hasWallet() async => true;

  @override
  Future<bool> isLocked() async => false;

  @override
  bool get isUnlocked => true;

  @override
  void lock() {}

  @override
  Future<bool> verifyPin(String pin) async => true;

  @override
  int get pinAttempts => 0;

  @override
  int get maxPinAttempts => 5;

  @override
  List<Vault> get vaults => const [];

  @override
  String? get activeVaultId => null;

  @override
  Vault? get activeVault => null;

  @override
  int? get sessionDepth => 0;

  @override
  bool get isStandInSession => false;

  @override
  Future<bool> hasStandIn() async => false;

  @override
  Future<StandInMode> standInMode() async => StandInMode.hide;

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
  }) async {}

  @override
  Future<void> updateStandInPin({
    required String oldPin,
    required String newPin,
  }) async {}

  @override
  Future<void> updateStandInMode({
    required String pin,
    required StandInMode mode,
  }) async {}

  @override
  Future<void> removeStandIn({required String pin}) async {}

  @override
  Future<void> switchVault(String id) async {}

  @override
  Future<void> renameVault(String id, String label) async {}

  @override
  Future<void> removeVault(String id, {required String pin}) async {}

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

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';

GoRouter _router(IWalletService ws) {
  return GoRouter(
    initialLocation: '/set-pin',
    routes: [
      GoRoute(
        path: '/set-pin',
        builder: (_, _) => SetPinScreen(
          mnemonic: _mnemonic,
          addVault: true,
          walletService: ws,
        ),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Home Screen'))),
      ),
    ],
  );
}

Future<void> _enterPin(WidgetTester tester, String digit) async {
  for (var i = 0; i < 6; i++) {
    await tester.tap(find.byKey(Key('pin-btn-$digit')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  // Flush the error-path reset delay (_resetPinWithDelay) so no timer is
  // left pending when the test ends.
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('addVault branch calls addVault and navigates home',
      (tester) async {
    final ws = _FakeWalletService();

    await tester.pumpWidget(
      MaterialApp.router(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        routerConfig: _router(ws),
      ),
    );
    await tester.pumpAndSettle();

    await _enterPin(tester, '1');

    expect(ws.addedPin, '111111');
    expect(ws.addedMnemonic, _mnemonic);
    expect(find.text('Home Screen'), findsOneWidget);
  });

  testWidgets('wrong session PIN shows an error and stays on the screen',
      (tester) async {
    // The service's mismatch message is mapped to the localized
    // "Incorrect PIN" rather than surfaced verbatim.
    final ws =
        _FakeWalletService(addVaultError: 'PIN does not match the current wallet.');

    await tester.pumpWidget(
      MaterialApp.router(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        routerConfig: _router(ws),
      ),
    );
    await tester.pumpAndSettle();

    await _enterPin(tester, '2');

    expect(find.text('Home Screen'), findsNothing);
    expect(find.text('Incorrect PIN'), findsOneWidget);
  });
}
