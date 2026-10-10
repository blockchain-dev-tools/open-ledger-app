// Widget tests for [AccountsTab] chain-section interaction.
//
// Regression: chain headers previously only responded to taps that landed
// directly on a child (icon / label / chevron) because the header
// GestureDetector used the default `HitTestBehavior.deferToChild`.
// Tapping the blank space inside the header must now toggle the section.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/accounts/accounts_tab.dart';

/// Minimal hand-written wallet service returning fixed accounts.
class _FakeWalletService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  _FakeWalletService(this._accounts);

  final WalletAccounts? _accounts;

  @override
  WalletAccounts? getAccounts() => _accounts;

  @override
  Future<WalletAccounts> addAccount(String chain, String path) async => _accounts!;

  @override
  Future<void> clearWallet() async {}

  @override
  Future<void> resetAll() async {}

  @override
  Future<bool> hasWallet() async => true;

  @override
  Future<bool> isLocked() async => false;

  @override
  bool get isUnlocked => true;

  @override
  void lock() {}

  @override
  String? get mnemonic => null;

  @override
  String? get passphrase => null;

  @override
  int get pinAttempts => 0;

  @override
  Future<WalletAccounts> removeAccount(String chain, String address) async =>
      _accounts!;

  @override
  Future<String?> revealMnemonic(String pin) async => null;

  @override
  String? get seedHex => null;

  @override
  Future<WalletAccounts> setupWallet(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async =>
      _accounts!;

  @override
  Future<WalletAccounts> unlockWallet(String pin) async => _accounts!;

  @override
  Future<bool> updatePin(String oldPin, String newPin) async => true;

  @override
  Future<bool> verifyPin(String pin) async => true;

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
  Future<WalletAccounts> addVault(
    String mnemonic, {
    required String pin,
    String passphrase = '',
    bool storePassphrase = false,
    String label = '',
    VaultSource source = VaultSource.imported,
    int enigmaLanguage = 0,
  }) async =>
      _accounts!;

  @override
  Future<void> removeVault(String id, {required String pin}) async {}
}

WalletAccounts _accounts() => const WalletAccounts(
      mnemonicFingerprint: '89bbb145',
      accounts: [
        ChainAccount(
          address: '0x9686bAAAAAAAAAAAAAAAAAAAdc989',
          derivationPath: "m/44'/60'/0'/0/0",
          publicKey: 'aa',
          chain: 'ethereum',
        ),
        ChainAccount(
          address: '0x25B24BBBBBBBBBBBBBBBBBB0F758',
          derivationPath: "m/44'/60'/0'/0/1",
          publicKey: 'bb',
          chain: 'ethereum',
        ),
        ChainAccount(
          address: 'SoLAAAA1111111111111111111111111111111111',
          derivationPath: "m/44'/501'/0'/0'",
          publicKey: 'cc',
          chain: 'solana',
        ),
      ],
    );

Widget _app(WalletAccounts accounts) {
  return MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: AccountsTab(walletService: _FakeWalletService(accounts)),
    ),
  );
}

void main() {
  testWidgets('chain sections start collapsed', (tester) async {
    await tester.pumpWidget(_app(_accounts()));
    await tester.pumpAndSettle();

    // Account rows hidden while collapsed.
    expect(find.text('0x9686b…dc989'), findsNothing);
    expect(find.text('0x25B24…0F758'), findsNothing);
  });

  testWidgets('tapping blank space in a chain header expands it',
      (tester) async {
    await tester.pumpWidget(_app(_accounts()));
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('chain-header-ethereum'));
    expect(header, findsOneWidget);

    final rect = tester.getRect(header);
    // A point ~15% in from the right edge: past the label, before the
    // chevron — i.e. visually empty space inside the header row.
    await tester.tapAt(Offset(rect.right - rect.width * 0.15, rect.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('0x9686b…dc989'), findsOneWidget);
    expect(find.text('0x25B24…0F758'), findsOneWidget);
  });

  testWidgets('tapping blank space again collapses the section',
      (tester) async {
    await tester.pumpWidget(_app(_accounts()));
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('chain-header-ethereum'));
    final rect = tester.getRect(header);
    final blankSpot =
        Offset(rect.right - rect.width * 0.15, rect.center.dy);

    await tester.tapAt(blankSpot);
    await tester.pumpAndSettle();
    expect(find.text('0x9686b…dc989'), findsOneWidget);

    await tester.tapAt(blankSpot);
    await tester.pumpAndSettle();
    expect(find.text('0x9686b…dc989'), findsNothing);
  });
}
