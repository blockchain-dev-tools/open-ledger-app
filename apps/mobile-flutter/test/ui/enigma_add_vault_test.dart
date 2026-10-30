// Widget tests for the Secret Phrase (Enigma) branch of the vault manager's
// "New Vault" flow: the flag must survive the mnemonic step and reach PIN setup.
//
// The Enigma screens derive words through the Rust bridge on a real device;
// this harness injects preview words instead (no FFI), so only navigation and
// the `addVault` hand-off are exercised.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/enigma/enigma_screen.dart';
import 'package:open_ledger_app/ui/screens/enigma_mnemonic/enigma_mnemonic_screen.dart';

/// BIP-39 256-bit zero-entropy vector — public, disposable.
const List<String> _words = [
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'art',
];

const String _entropyHex =
    '0000000000000000000000000000000000000000000000000000000000000000';

GoRouter _router() => GoRouter(
      initialLocation: '/enigma',
      routes: [
        GoRoute(
          path: '/enigma',
          builder: (context, state) {
            final extra = state.extra;
            final addVault = extra is Map && extra['addVault'] == true;
            return EnigmaScreen(addVault: addVault);
          },
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

Future<void> _tapContinue(WidgetTester tester) async {
  final button = find.byKey(const Key('enigma-mnemonic-continue'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new-vault mnemonic step passes addVault to PIN setup',
      (tester) async {
    final router = _router();
    await _pump(tester, router);

    router.push('/enigma-mnemonic', extra: const {'addVault': true});
    await tester.pumpAndSettle();
    await _tapContinue(tester);

    expect(find.text('set-pin addVault=true'), findsOneWidget);
  });

  testWidgets('first-run mnemonic step still passes addVault=false',
      (tester) async {
    final router = _router();
    await _pump(tester, router);

    router.push('/enigma-mnemonic', extra: const {'addVault': false});
    await tester.pumpAndSettle();
    await _tapContinue(tester);

    expect(find.text('set-pin addVault=false'), findsOneWidget);
  });

  testWidgets('new-vault mnemonic step goes back to the secret phrase screen',
      (tester) async {
    final router = _router();
    await _pump(tester, router);

    router.push('/enigma-mnemonic', extra: const {'addVault': true});
    await tester.pumpAndSettle();

    // The topmost route's back affordance: the pushed mnemonic screen.
    await tester.tap(find.byIcon(Icons.arrow_back).last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('enigma-riddle')), findsOneWidget);
    expect(find.byKey(const Key('enigma-mnemonic-continue')), findsNothing);
  });
}
