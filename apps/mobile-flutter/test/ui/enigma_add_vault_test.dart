// Widget tests for the Secret Phrase (Enigma) tab of the vault manager's
// "New Vault" flow: the tab renders the form in place and the `addVault` flag
// must survive the word review and reach PIN setup.
//
// Deriving needs the Rust bridge on a real device; this harness injects a
// fake derivation (no FFI) and a preview word list, so only the in-place
// switch and the addVault hand-off are exercised.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/data/bip39_wordlist.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/services/mnemonic_service.dart';
import 'package:open_ledger_app/ui/screens/enigma_mnemonic/enigma_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/import_mnemonic/import_mnemonic_screen.dart';

import '../support/fake_crypto_service.dart';

/// BIP-39 256-bit zero-entropy vector — public, disposable.
const List<String> _words = [
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'art',
];

const String _entropyHex =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// Stands in for `generateEnigmaMnemonic` (the native bridge is absent here).
({List<String> words, String entropyHex}) _fakeDerive(
  String riddle,
  String secret, {
  Bip39WordlistLanguage language = Bip39WordlistLanguage.english,
}) =>
    (words: _words, entropyHex: _entropyHex);

/// Accepts both supported BIP-39 lengths (checksum verification is Rust-owned).
class _ValidatingCrypto extends FakeCryptoService {
  const _ValidatingCrypto();

  @override
  bool validateMnemonic(String mnemonic) {
    final count = mnemonic
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return count == 12 || count == 24;
  }
}

GoRouter _router() => GoRouter(
      initialLocation: '/import',
      routes: [
        GoRoute(
          path: '/import',
          builder: (context, state) => ImportMnemonicScreen(
            mnemonicService: MnemonicService(crypto: const _ValidatingCrypto()),
            addVault: true,
            enigmaDerive: _fakeDerive,
          ),
        ),
        GoRoute(
          path: '/enigma-mnemonic',
          builder: (context, state) {
            final extra = state.extra;
            final addVault = extra is Map && extra['addVault'] == true;
            return EnigmaMnemonicScreen(
              previewWords: _words,
              previewEntropyHex: _entropyHex,
              addVault: addVault,
            );
          },
        ),
        GoRoute(
          path: '/set-pin',
          builder: (context, state) {
            final extra = state.extra as Map;
            return Scaffold(
              body: Text('set-pin addVault=${extra['addVault']}'),
            );
          },
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
  await tester.pumpAndSettle();
}

/// Fills the secret-phrase tab and taps Generate, waiting out its 300 ms
/// processing delay.
Future<void> _generate(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('enigma-riddle')),
    'second vault add abandon',
  );
  await tester.enterText(
    find.byKey(const Key('enigma-secret')),
    'vault-two-key',
  );
  await tester.pump();

  final button = find.byKey(const Key('enigma-generate'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _tapContinue(WidgetTester tester) async {
  final button = find.byKey(const Key('enigma-mnemonic-continue'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('generating on the tab goes to the review step in place of the '
      'form', (tester) async {
    final router = _router();
    await _pump(tester, router);

    await tester.tap(find.byKey(const Key('add-vault-tab-secret')));
    await tester.pumpAndSettle();

    // The tab is a switch, not a route: still the import screen.
    expect(find.byType(ImportMnemonicScreen), findsOneWidget);
    expect(find.byKey(const Key('enigma-riddle')), findsOneWidget);

    await _generate(tester);

    expect(find.byKey(const Key('enigma-mnemonic-continue')), findsOneWidget);
    expect(router.state.uri.path, '/enigma-mnemonic');
  });

  testWidgets('new-vault review step passes addVault to PIN setup',
      (tester) async {
    final router = _router();
    await _pump(tester, router);

    await tester.tap(find.byKey(const Key('add-vault-tab-secret')));
    await tester.pumpAndSettle();
    await _generate(tester);
    await _tapContinue(tester);

    expect(find.text('set-pin addVault=true'), findsOneWidget);
  });

  testWidgets('back from the review step keeps the tab and the riddle',
      (tester) async {
    final router = _router();
    await _pump(tester, router);

    await tester.tap(find.byKey(const Key('add-vault-tab-secret')));
    await tester.pumpAndSettle();
    await _generate(tester);

    // The topmost route's back affordance: the pushed review screen.
    await tester.tap(find.byIcon(Icons.arrow_back).last);
    await tester.pumpAndSettle();

    expect(find.byType(ImportMnemonicScreen), findsOneWidget);
    expect(find.byKey(const Key('enigma-mnemonic-continue')), findsNothing);

    final riddle = tester
        .widget<TextField>(find.byKey(const Key('enigma-riddle')))
        .controller!
        .text;
    expect(riddle, 'second vault add abandon');
  });
}
