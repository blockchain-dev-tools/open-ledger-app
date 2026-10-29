// Widget tests for [AccountsTab] chain-section interaction.
//
// Regression: chain headers previously only responded to taps that landed
// directly on a child (icon / label / chevron) because the header
// GestureDetector used the default `HitTestBehavior.deferToChild`.
// Tapping the blank space inside the header must now toggle the section.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/accounts/accounts_tab.dart';
import 'package:open_ledger_app/ui/screens/seed_export/private_key_list_screen.dart';

/// Minimal hand-written wallet service returning fixed accounts.
class _FakeWalletService implements IWalletService {
  @override
  void Function()? onActiveVaultChanged;

  @override
  void Function(Set<String> vaultIds)? onVaultsDestroyed;

  @override
  Future<bool> verifySessionPin(String pin) async => true;
  _FakeWalletService(this._accounts);

  WalletAccounts? _accounts;

  /// Chains turned off in "Manage chains".
  final Set<String> _hidden = {};

  @override
  WalletAccounts? getAccounts() => _accounts;

  @override
  Future<WalletAccounts> addAccount(String chain, String path) async {
    final accounts = _accounts;
    if (accounts == null) {
      return WalletAccounts(accounts: const [], mnemonicFingerprint: 'test');
    }
    _accounts = accounts.copyWith(accounts: [
      ...accounts.accounts,
      ChainAccount(
        address: 'added-$chain',
        derivationPath: path,
        publicKey: 'aa',
        chain: chain,
      ),
    ]);
    return _accounts!;
  }

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
  int get maxPinAttempts => 5;

  @override
  Future<WalletAccounts> removeAccount(String chain, String address) async =>
      _accounts!;

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

Widget _app(WalletAccounts accounts, {_FakeWalletService? service}) {
  return MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: AccountsTab(walletService: service ?? _FakeWalletService(accounts)),
    ),
  );
}

void main() {
  // The default four plus Sui (as if it had been added from the sheet);
  // NEAR/TON are deliberately absent so the "hidden until added" rule shows.
  final allAccounts = WalletAccounts(
    mnemonicFingerprint: 'test',
    accounts: [
      for (final chain in [...Chain.defaultVisible, Chain.sui])
        ChainAccount(
          address: 'test-${chain.id}',
          derivationPath: chain.defaultAccountPath,
          publicKey: 'aa',
          chain: chain.id,
        ),
    ],
  );

  for (final brightness in Brightness.values) {
    testWidgets('shows the default chains plus any chain with an account in '
        '$brightness', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AccountsTab(walletService: _FakeWalletService(allAccounts)),
        ),
      ));
      await tester.pumpAndSettle();
      // Default four, plus Sui because the fixture already derives one.
      for (final chain in ['bitcoin', 'ethereum', 'solana', 'tron', 'sui']) {
        expect(find.byKey(ValueKey('chain-header-$chain')), findsOneWidget);
      }
      // Never-enabled chains stay hidden.
      for (final chain in ['near', 'ton']) {
        expect(find.byKey(ValueKey('chain-header-$chain')), findsNothing);
      }
      expect(find.byKey(const ValueKey('manage-chains-tile')), findsOneWidget);
      expect(allAccounts.accounts, hasLength(5));
    });

    testWidgets('lists every derived account\'s private key in $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrivateKeyListScreen(accounts: allAccounts.accounts),
      ));
      await tester.pumpAndSettle();
      for (final chain in Chain.values) {
        if (!allAccounts.accounts.any((a) => a.chain == chain.id)) continue;
        expect(find.text(chain.defaultAccountPath), findsOneWidget);
      }
      expect(allAccounts.accounts, hasLength(5));
    });
  }

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

  testWidgets('manage chains toggles a chain off and on', (tester) async {
    final service = _FakeWalletService(allAccounts);
    await tester.pumpWidget(_app(allAccounts, service: service));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chain-header-ethereum')), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-header-near')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('manage-chains-tile')));
    await tester.pumpAndSettle();

    // Every chain is listed with a switch — added and not-yet-added alike.
    for (final chain in Chain.withLedgerApp) {
      expect(find.byKey(ValueKey('chain-toggle-${chain.id}')), findsOneWidget);
    }
    expect(
      tester.widget<Switch>(find.byKey(const ValueKey('chain-toggle-sui'))).value,
      isTrue,
      reason: 'the fixture already derives a Sui account',
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('chain-toggle-near')))
          .value,
      isFalse,
    );

    // Turning Ethereum off hides its section (accounts are kept).
    await tester.tap(find.byKey(const ValueKey('chain-toggle-ethereum')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain-header-ethereum')), findsNothing);
    expect(service.hiddenChains, contains('ethereum'));
    // Turning NEAR on derives account 0 and reveals its section.
    await tester.tap(find.byKey(const ValueKey('chain-toggle-near')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain-header-near')), findsOneWidget);

    // Turning Ethereum back on reuses its account — nothing is re-derived.
    await tester.tap(find.byKey(const ValueKey('chain-toggle-ethereum')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain-header-ethereum')), findsOneWidget);
    expect(service.hiddenChains, isNot(contains('ethereum')));
  });
}
