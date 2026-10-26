// Widget tests for [StandInScreen] (ADR-009) — the first-time wizard, the
// configured status view, and nested-session access.
//
// Covers:
// - not configured → complete the wizard → configureStandIn with exact args
// - selecting wipe mode requires a second confirmation, and the chosen mode
//   flows through to configureStandIn
// - a stand-in session can still run the wizard (it nests one tier deeper)
// - configured → remove requires the main PIN

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/mnemonic_service.dart';
import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/core/models/vault.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/import_mnemonic/components/mnemonic_suggestions.dart';
import 'package:open_ledger_app/ui/screens/stand_in/stand_in_screen.dart';

import '../support/fake_wallet_service.dart';

const String _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

/// Fixed 24-word phrase returned by the fake Enigma derivation.
const List<String> _enigmaWords = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
  'account', 'accuse', 'achieve', 'acid', 'acoustic', 'acquire',
  'across', 'act', 'action', 'actor', 'actress', 'actual',
];

class _FakeMnemonic implements IMnemonicService {
  /// Records the arguments of each Enigma derivation.
  final List<({String riddle, String secret, int language})> enigmaCalls = [];

  @override
  String generateMnemonic({int strength = 128}) => _mnemonic;

  @override
  bool validateMnemonic(String mnemonic) {
    final count = mnemonic
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return count == 12 || count == 24;
  }

  @override
  String mnemonicToSeedHex(String mnemonic, String passphrase) => '';

  @override
  String fingerprintMnemonic(String mnemonic) => '00000000';

  @override
  List<String> generateEnigmaMnemonic(
    String riddle,
    String secret, {
    int language = 0,
  }) {
    enigmaCalls.add((riddle: riddle, secret: secret, language: language));
    return _enigmaWords;
  }
}

Widget _app(IWalletService ws, {IMnemonicService? mnemonic}) => MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: StandInScreen(
        walletService: ws,
        mnemonicService: mnemonic ?? _FakeMnemonic(),
      ),
    );

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('standin-pin-btn-$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Runs the wizard from the intro step through the main-PIN submission,
/// importing the fixed phrase.
Future<void> _completeWizard(
  WidgetTester tester, {
  required String pin,
  required String mainPin,
}) async {
  await tester.tap(find.byKey(const Key('standin-intro-continue')));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('standin-mnemonic-input')),
    _mnemonic,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('standin-import-continue')));
  await tester.pumpAndSettle();

  await _enterPin(tester, pin);
  await _enterPin(tester, pin);
  await _enterPin(tester, mainPin);
}

void main() {
  testWidgets('not configured → wizard completes with the right arguments',
      (tester) async {
    final ws = FakeWalletService();

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    // Intro (threat model + mode selection) is shown.
    expect(find.text('What this protects'), findsOneWidget);

    await _completeWizard(tester, pin: '111111', mainPin: '999999');

    expect(ws.configureCalls, hasLength(1));
    final call = ws.configureCalls.single;
    expect(call.mnemonic, _mnemonic);
    expect(call.pin, '111111');
    expect(call.mainPin, '999999');
    expect(call.mode, StandInMode.hide);

    // Lands on the configured status view.
    expect(find.text('Set up'), findsOneWidget);
  });

  testWidgets('wipe mode needs confirmation and is passed through',
      (tester) async {
    final ws = FakeWalletService();

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    // Selecting wipe opens the second confirmation.
    await tester.tap(find.byKey(const ValueKey('standin-mode-wipe')));
    await tester.pumpAndSettle();
    expect(find.text('Use erase mode?'), findsOneWidget);

    // Cancelling leaves the default (hide) untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Use erase mode?'), findsNothing);

    // Confirming selects wipe.
    await tester.tap(find.byKey(const ValueKey('standin-mode-wipe')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Switch & erase'));
    await tester.pumpAndSettle();
    expect(find.text('Use erase mode?'), findsNothing);

    // The run proceeds and the mode reaches the service.
    await _completeWizard(tester, pin: '222222', mainPin: '999999');
    expect(ws.configureCalls.single.mode, StandInMode.wipe);
  });

  testWidgets('a stand-in session can configure a nested stand-in',
      (tester) async {
    // A stand-in session is reachable from Settings → Stand-in Wallet, and may
    // itself configure a stand-in one tier deeper.
    final ws = FakeWalletService(isStandInSession: true);

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    // The wizard is reachable — no "unavailable" state.
    expect(find.text('What this protects'), findsOneWidget);
    expect(find.text('Not available in this session.'), findsNothing);

    await _completeWizard(tester, pin: '111111', mainPin: '222222');

    expect(ws.configureCalls, hasLength(1));
    expect(ws.configureCalls.single.mainPin, '222222');
    // Lands on the configured status view.
    expect(find.text('Set up'), findsOneWidget);
  });

  testWidgets('configured → remove requires the main PIN', (tester) async {
    final ws = FakeWalletService(standInConfigured: true);

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();
    expect(find.text('Set up'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('standin-action-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove stand-in wallet'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Remove stand-in wallet'));
    await tester.pumpAndSettle();

    await _enterPin(tester, '999999');
    expect(ws.removePins, ['999999']);
    // Back to the (unconfigured) wizard intro.
    expect(find.text('What this protects'), findsOneWidget);
  });

  testWidgets('enigma path derives 24 words and configures the stand-in',
      (tester) async {
    final ws = FakeWalletService();
    final mnemo = _FakeMnemonic();

    await tester.pumpWidget(_app(ws, mnemonic: mnemo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('standin-intro-continue')));
    await tester.pumpAndSettle();

    // Three creation modes share the step, import first.
    expect(find.byKey(const ValueKey('standin-tab-import')), findsOneWidget);
    expect(find.byKey(const ValueKey('standin-tab-generate')), findsOneWidget);
    expect(find.byKey(const ValueKey('standin-tab-enigma')), findsOneWidget);

    // Third tab hosts the Enigma flow.
    await tester.tap(find.byKey(const ValueKey('standin-tab-enigma')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('standin-enigma-riddle')), findsOneWidget);
    expect(find.byKey(const Key('standin-enigma-secret')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('standin-enigma-riddle')),
      'my riddle',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('standin-enigma-secret')),
      'my secret',
    );
    await tester.pump();

    // Select the Chinese wordlist so the language index flows through.
    await tester
        .ensureVisible(find.byKey(const ValueKey('standin-enigma-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('standin-enigma-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('standin-enigma-generate')));
    await tester.pumpAndSettle();

    // The 24-word grid is shown; continue is gated on the write-down box.
    expect(find.text('1. abandon'), findsOneWidget);
    expect(find.text('24. actual'), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const ValueKey('standin-enigma-written-down')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('standin-enigma-written-down')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('standin-enigma-continue')));
    await tester.pumpAndSettle();

    await _enterPin(tester, '111111');
    await _enterPin(tester, '111111');
    await _enterPin(tester, '999999');

    expect(mnemo.enigmaCalls, hasLength(1));
    expect(mnemo.enigmaCalls.single.riddle, 'my riddle');
    expect(mnemo.enigmaCalls.single.secret, 'my secret');
    // Bip39WordlistLanguage.chineseSimplified.index == 1.
    expect(mnemo.enigmaCalls.single.language, 1);

    expect(ws.configureCalls, hasLength(1));
    final call = ws.configureCalls.single;
    expect(call.mnemonic, _enigmaWords.join(' '));
    expect(call.pin, '111111');
    expect(call.mainPin, '999999');
    expect(call.mode, StandInMode.hide);

    // Lands on the configured status view.
    expect(find.text('Set up'), findsOneWidget);
  });

  testWidgets('import tab accepts a 24-word phrase', (tester) async {
    final ws = FakeWalletService();

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('standin-intro-continue')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('standin-mnemonic-input')),
      _enigmaWords.join(' '),
    );
    await tester.pump();

    expect(find.text('24 / 24 words'), findsOneWidget);
    expect(find.text('Valid recovery phrase'), findsOneWidget);

    await tester.tap(find.byKey(const Key('standin-import-continue')));
    await tester.pumpAndSettle();
    await _enterPin(tester, '111111');
    await _enterPin(tester, '111111');
    await _enterPin(tester, '999999');

    expect(ws.configureCalls.single.mnemonic, _enigmaWords.join(' '));
  });

  testWidgets('import tab offers and applies BIP-39 prefix suggestions',
      (tester) async {
    final ws = FakeWalletService();

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('standin-intro-continue')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('standin-mnemonic-input')),
      'aban',
    );
    await tester.pump();
    expect(
      find.byKey(MnemonicSuggestions.keyFor('abandon')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(MnemonicSuggestions.keyFor('abandon')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('standin-mnemonic-input')),
    );
    expect(field.controller!.text, 'abandon ');
  });
}
