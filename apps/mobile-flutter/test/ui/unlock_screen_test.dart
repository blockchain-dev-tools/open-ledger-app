/// Widget tests for [UnlockScreen].
///
/// Covers:
/// - Reset via "Forgot PIN?" link → calls resetAll → navigates to welcome
/// - Reset after lockout → calls resetAll → navigates to welcome
library;
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/ui/screens/unlock/unlock_screen.dart';
import 'package:open_ledger_app/ui/theme/widgets/brand_mark.dart';
import 'package:open_ledger_app/ui/widgets/pin/pin_dot_indicator.dart';

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
  bool clearWalletCalled = false;
  bool resetAllCalled = false;
  bool _isLockedResult = false;
  final bool _verifyPinResult = true;

  void setLocked() {
    _isLockedResult = true;
  }

  @override
  Future<bool> isLocked() => Future.value(_isLockedResult);

  @override
  Future<bool> verifyPin(String pin) => Future.value(_verifyPinResult);

  @override
  Future<void> clearWallet() async {
    clearWalletCalled = true;
  }

  @override
  Future<void> resetAll() async {
    resetAllCalled = true;
  }

  // ── Unused stubs ────────────────────────────────────────────────────

  @override
  Future<bool> hasWallet() => Future.value(true);

  @override
  bool get isUnlocked => false;

  @override
  void lock() {}

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

GoRouter _testRouter({required Widget unlockScreen}) => GoRouter(
      initialLocation: '/unlock',
      routes: [
        GoRoute(
          path: '/unlock',
          builder: (_, _) => unlockScreen,
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Welcome Screen')),
          ),
        ),
        GoRoute(
          path: '/vault',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Vault Screen')),
          ),
        ),
      ],
    );

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  testWidgets('forgot PIN confirms before resetting the wallet',
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
          unlockScreen: UnlockScreen(
            walletService: mockWallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // "Forgot PIN?" is at the bottom of the scrollable column.
    // Scroll down to reveal it.
    await tester.scrollUntilVisible(
      find.text('Forgot PIN?'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tapping the link opens the confirmation dialog; nothing is destroyed
    // until the user confirms (T-019).
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Are you sure'), findsOneWidget);
    expect(mockWallet.resetAllCalled, isFalse);

    await tester.tap(find.byKey(const Key('reset-wallet-confirm')));
    await tester.pumpAndSettle();

    // Verify: resetAll was called (not the session-scoped clearWallet)
    expect(mockWallet.resetAllCalled, isTrue);
    expect(mockWallet.clearWalletCalled, isFalse);

    // Verify: navigated to /welcome
    expect(find.text('Welcome Screen'), findsOneWidget);
  });

  testWidgets('cancelling the forgot-PIN dialog keeps the wallet',
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
          unlockScreen: UnlockScreen(
            walletService: mockWallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Forgot PIN?'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-wallet-cancel')));
    await tester.pumpAndSettle();

    expect(mockWallet.resetAllCalled, isFalse);
    // Still on the PIN entry screen.
    expect(find.text('Enter PIN'), findsOneWidget);
  });

  testWidgets('an already locked-out wallet shows the lockout view on entry',
      (tester) async {
    final mockWallet = _MockWalletService();
    mockWallet.setLocked();

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
          unlockScreen: UnlockScreen(
            walletService: mockWallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No PIN entry at all: the persisted lockout is checked on entry, so the
    // pad must never appear.
    expect(find.byKey(const Key('unlock-btn-1')), findsNothing);
    // The lockout view is one mark, one title, and no dead input affordances:
    // the brand mark, the PIN dots and the duplicate headline are all gone
    // (T-019).
    expect(find.byType(PinDotIndicator), findsNothing);
    expect(find.byType(BrandMark), findsNothing);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.text('Locked out'), findsOneWidget);

    // The destructive action is labelled once and asks for confirmation.
    expect(find.text('Reset Wallet'), findsOneWidget);
    expect(find.textContaining('without a backup'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('reset-wallet')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-wallet')));
    await tester.pumpAndSettle();

    expect(mockWallet.resetAllCalled, isFalse);
    expect(find.textContaining('Are you sure'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reset-wallet-confirm')));
    await tester.pumpAndSettle();

    // Verify: resetAll was called (not the session-scoped clearWallet)
    expect(mockWallet.resetAllCalled, isTrue);
    expect(mockWallet.clearWalletCalled, isFalse);

    // Verify: navigated to /welcome
    expect(find.text('Welcome Screen'), findsOneWidget);
  });
}
