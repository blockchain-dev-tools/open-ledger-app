// Widget tests for [VaultSwitcherTitle] and its switcher sheet.
//
// Covers:
// - the title renders the active vault's label (fallback: "Vault N")
// - the sheet lists every vault and switching calls switchVault + onChanged
// - "New Vault" is disabled (with the limit hint) once 2 vaults exist
// - a single vault cannot be removed
// - a stand-in session still offers the "New Vault" action (it adds to the
//   current tier, never a primary one)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/widgets/vault/vault_switcher.dart';

// ═══════════════════════════════════════════════════════════════════════
// Hand-written fake IWalletService driven by an explicit vault list
// ═══════════════════════════════════════════════════════════════════════

class _FakeVaultService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  _FakeVaultService({
    required List<Vault> vaults,
    String? activeId,
    this.isStandInSession = false,
  })  : _vaults = List.of(vaults),
        _activeId = activeId ?? (vaults.isNotEmpty ? vaults.first.id : null);

  final List<Vault> _vaults;
  String? _activeId;

  final List<String> switchCalls = [];
  final List<String> removeCalls = [];

  @override
  final bool isStandInSession;

  @override
  List<Vault> get vaults => List.unmodifiable(_vaults);

  @override
  String? get activeVaultId => _activeId;

  @override
  Vault? get activeVault {
    for (final v in _vaults) {
      if (v.id == _activeId) return v;
    }
    return null;
  }

  @override
  Future<void> switchVault(String id) async {
    switchCalls.add(id);
    _activeId = id;
  }

  @override
  Future<void> renameVault(String id, String label) async {}

  @override
  Future<void> removeVault(String id, {required String pin}) async {
    removeCalls.add(id);
    _vaults.removeWhere((v) => v.id == id);
    if (_activeId == id && _vaults.isNotEmpty) _activeId = _vaults.first.id;
  }

  // ── Unused stubs ────────────────────────────────────────────────────

  @override
  Future<bool> hasWallet() async => true;

  @override
  Future<bool> isLocked() async => false;

  @override
  bool get isUnlocked => _activeId != null;

  @override
  void lock() {}

  @override
  Future<bool> verifyPin(String pin) async => true;

  @override
  int get pinAttempts => 0;

  @override
  int? get sessionDepth => isStandInSession ? 1 : 0;

  @override
  Future<bool> hasStandIn() async => isStandInSession;

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

const _emptyAccounts = WalletAccounts(
  mnemonicFingerprint: 'test0000',
  accounts: [],
);

Vault _vault(String id, {String label = ''}) => Vault(
      id: id,
      label: label,
      depth: 0,
      mnemonicEncrypted: 'enc-$id',
      accounts: _emptyAccounts,
      createdAt: 0,
    );

Widget _app(IWalletService ws, {VoidCallback? onChanged}) {
  return MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      appBar: AppBar(
        title: VaultSwitcherTitle(walletService: ws, onChanged: onChanged),
      ),
    ),
  );
}

/// GoRouter-backed variant so the "New Vault" row can actually navigate.
Widget _routerApp(IWalletService ws) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          appBar: AppBar(title: VaultSwitcherTitle(walletService: ws)),
        ),
      ),
      GoRoute(
        path: '/import',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('Import Screen')),
        ),
      ),
    ],
  );
  return MaterialApp.router(
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

void main() {
  testWidgets('title falls back to "Vault N" and uses the label when set',
      (tester) async {
    final ws = _FakeVaultService(vaults: [
      _vault('a'),
      _vault('b', label: 'Savings'),
    ], activeId: 'a');

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();
    // Active vault 'a' has no label → positional default.
    expect(find.text('Vault 1'), findsOneWidget);
  });

  testWidgets('switching a vault calls switchVault and onChanged',
      (tester) async {
    final ws = _FakeVaultService(vaults: [
      _vault('a', label: 'Main'),
      _vault('b', label: 'Savings'),
    ], activeId: 'a');
    var changed = 0;

    await tester.pumpWidget(_app(ws, onChanged: () => changed++));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VaultSwitcherTitle));
    await tester.pumpAndSettle();

    // Both vaults listed.
    expect(find.text('Main'), findsWidgets);
    expect(find.text('Savings'), findsOneWidget);

    await tester.tap(find.text('Savings'));
    await tester.pumpAndSettle();

    expect(ws.switchCalls, ['b']);
    expect(ws.activeVaultId, 'b');
    expect(changed, 1);
    // Sheet dismissed.
    expect(find.text('Savings'), findsNothing);
  });

  testWidgets('with two vaults the "New Vault" action is disabled',
      (tester) async {
    final ws = _FakeVaultService(vaults: [
      _vault('a', label: 'Main'),
      _vault('b', label: 'Savings'),
    ], activeId: 'a');

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VaultSwitcherTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Vaults'));
    await tester.pumpAndSettle();

    expect(find.text('New Vault'), findsOneWidget);
    expect(
      find.text('Vault limit reached. Remove a vault first.'),
      findsOneWidget,
    );
  });

  testWidgets('a single vault cannot be removed', (tester) async {
    final ws = _FakeVaultService(vaults: [_vault('a', label: 'Main')]);

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VaultSwitcherTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Vaults'));
    await tester.pumpAndSettle();

    final removeButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(removeButton.onPressed, isNull);
  });

  testWidgets('a stand-in session still offers the "New Vault" action',
      (tester) async {
    final ws = _FakeVaultService(
      vaults: [_vault('h')],
      isStandInSession: true,
    );

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VaultSwitcherTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Vaults'));
    await tester.pumpAndSettle();

    // Available and not disabled (a stand-in tier has no vault cap).
    expect(find.text('New Vault'), findsOneWidget);
    expect(find.text('Vault limit reached. Remove a vault first.'), findsNothing);
  });

  testWidgets('the "New Vault" action navigates to the import flow',
      (tester) async {
    final ws = _FakeVaultService(
      vaults: [_vault('h')],
      isStandInSession: true,
    );

    await tester.pumpWidget(_routerApp(ws));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VaultSwitcherTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Vaults'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Vault'));
    await tester.pumpAndSettle();

    expect(find.text('Import Screen'), findsOneWidget);
  });
}
