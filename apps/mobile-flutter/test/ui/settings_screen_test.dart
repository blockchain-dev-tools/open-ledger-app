/// Widget tests for [SettingsScreen].
///
/// Covers:
/// - Reset Wallet flow: confirmation dialog → calls resetAll → navigates
library;
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/core/interfaces/settings_repository.dart';
import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/launcher_disguise.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/services/settings_service.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/settings/settings_screen.dart';

/// In-memory ISettingsRepository for the theme-picker test.
class _InMemorySettingsRepo implements ISettingsRepository {
  ThemeMode mode = ThemeMode.dark;

  @override
  Future<SettingsData> loadSettings() async =>
      SettingsData(themeMode: mode);

  @override
  Future<void> setThemeMode(ThemeMode m) async => mode = m;

  @override
  Future<void> setLocale(Locale locale) async {}

  @override
  Future<void> setStorePassphrase(bool value) async {}

  @override
  Future<void> setLauncherDisguise(LauncherDisguise value) async {}

  @override
  Future<void> setBleName(String value) async {}
}

// ═══════════════════════════════════════════════════════════════════════
// Hand-written Mock IWalletService
// ═══════════════════════════════════════════════════════════════════════

class _MockWalletService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  bool resetAllCalled = false;

  @override
  Future<void> clearWallet() async {}

  @override
  Future<void> resetAll() async {
    resetAllCalled = true;
  }

  // ── Unused stubs ────────────────────────────────────────────────────

  @override
  Future<bool> hasWallet() => Future.value(false);

  @override
  Future<bool> isLocked() => Future.value(false);

  @override
  bool get isUnlocked => false;

  @override
  void lock() {}

  @override
  Future<bool> verifyPin(String pin) => Future.value(true);

  @override
  int get pinAttempts => 0;

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
  }) =>
      throw UnimplementedError();

  @override
  Future<WalletAccounts> unlockWallet(String pin) =>
      throw UnimplementedError();

  @override
  WalletAccounts? getAccounts() => null;

  @override
  Future<WalletAccounts> addAccount(String chain, String path) =>
      throw UnimplementedError();

  @override
  Future<WalletAccounts> removeAccount(String chain, String address) =>
      throw UnimplementedError();

  @override
  Future<String?> revealMnemonic(String pin) => Future.value(null);

  @override
  String? get seedHex => null;

  @override
  String? get mnemonic => null;

  @override
  String? get passphrase => null;

  @override
  Future<bool> updatePin(String oldPin, String newPin) =>
      Future.value(true);

  // ── Multi-vault session stubs (unused by these tests) ───────────────

  @override
  List<Vault> get vaults => const [];

  @override
  String? get activeVaultId => null;

  @override
  Vault? get activeVault => null;

  @override
  int? get sessionDepth => null;

  @override
  bool get isStandInSession => false;

  @override
  Future<bool> hasStandIn() => Future.value(false);

  @override
  Future<StandInMode> standInMode() => Future.value(StandInMode.hide);

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
  Future<WalletAccounts> addVault(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    String label = '',
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removeVault(String id, {required String pin}) =>
      throw UnimplementedError();
}

// ═══════════════════════════════════════════════════════════════════════
// Test helper: builds a GoRouter with only the routes needed by the test
// ═══════════════════════════════════════════════════════════════════════

GoRouter _testRouter({required Widget settingsScreen}) => GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => settingsScreen,
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Welcome Screen')),
          ),
        ),
      ],
    );

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  testWidgets('reset wallet calls resetAll and navigates to welcome',
      (tester) async {
    final mockWallet = _MockWalletService();

    await tester.pumpWidget(
      MaterialApp.router(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _testRouter(
          settingsScreen: SettingsScreen(
            walletService: mockWallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll down to find the "Reset Wallet" tile
    await tester.scrollUntilVisible(
      find.text('Reset Wallet'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tap "Reset Wallet"
    await tester.tap(find.text('Reset Wallet'));
    await tester.pumpAndSettle();

    // Confirm dialog should appear — use textContaining since the Text
    // widget renders the full paragraph including "Are you sure?"
    expect(
      find.textContaining('Are you sure'),
      findsOneWidget,
    );

    // Tap "Reset" in the confirmation dialog
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    // Verify: resetAll was called
    expect(mockWallet.resetAllCalled, isTrue);

    // Verify: navigated to /welcome
    expect(find.text('Welcome Screen'), findsOneWidget);
  });

  testWidgets('reset wallet dialog can be cancelled', (tester) async {
    final mockWallet = _MockWalletService();

    await tester.pumpWidget(
      MaterialApp.router(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _testRouter(
          settingsScreen: SettingsScreen(
            walletService: mockWallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to Reset Wallet tile
    await tester.scrollUntilVisible(
      find.text('Reset Wallet'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tap "Reset Wallet"
    await tester.tap(find.text('Reset Wallet'));
    await tester.pumpAndSettle();

    // Confirm dialog visible
    expect(find.textContaining('Are you sure'), findsOneWidget);

    // Tap "Cancel"
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Verify: resetAll was NOT called
    expect(mockWallet.resetAllCalled, isFalse);

    // Verify: still on settings screen
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
      'theme row opens picker sheet with 3 options and applies selection',
      (tester) async {
    final service = SettingsService(repo: _InMemorySettingsRepo());

    await tester.pumpWidget(
      MaterialApp.router(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _testRouter(
          settingsScreen: SettingsScreen(settingsService: service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the theme picker sheet.
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    // The service default is now ThemeMode.system, so the row's current value
    // is "System" — which then also appears as a sheet option.
    expect(find.text('System'), findsNWidgets(2));
    expect(find.text('Light Mode'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);

    await tester.tap(find.text('Light Mode'));
    await tester.pumpAndSettle();

    expect(service.themeMode, ThemeMode.light);
    // Sheet dismissed; the row value now shows the new selection.
    expect(find.text('Light Mode'), findsOneWidget);
  });
}
