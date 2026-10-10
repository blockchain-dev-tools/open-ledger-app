// Widget tests for the Stand-in Wallet row in Settings → Security (ADR-009).
//
// The row is *always* tappable and always shows its real, session-relative
// status — no session makes it behave differently (that asymmetry was itself
// an observable tell):
// - primary session shows the top-level stand-in status;
// - a stand-in session shows its own nested status ("Not set up" when it has
//   no child tier yet).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/settings/settings_screen.dart';

import '../support/fake_wallet_service.dart';

Widget _app(IWalletService ws) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => SettingsScreen(walletService: ws),
      ),
      GoRoute(
        path: '/stand-in',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('Stand-in Screen')),
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

/// The InkWell that backs the "Stand-in Wallet" row.
InkWell _standInRowInk(WidgetTester tester) {
  final finder = find
      .ancestor(
        of: find.text('Stand-in Wallet'),
        matching: find.byType(InkWell),
      )
      .first;
  return tester.widget<InkWell>(finder);
}

void main() {
  testWidgets('primary session shows real status and is tappable',
      (tester) async {
    final ws = FakeWalletService(standInConfigured: true);

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    expect(find.text('Stand-in Wallet'), findsOneWidget);
    expect(find.text('Set up'), findsOneWidget);
    expect(_standInRowInk(tester).onTap, isNotNull);
  });

  testWidgets('primary session without a stand-in shows the setup path',
      (tester) async {
    final ws = FakeWalletService();

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    expect(find.text('Not set up'), findsOneWidget);
    expect(_standInRowInk(tester).onTap, isNotNull);
  });

  testWidgets('stand-in session row stays tappable and reads "Not set up"',
      (tester) async {
    // The stand-in session has no nested child tier yet; the row must not be
    // inert (its inertness was the disguise tell this change removes).
    final ws = FakeWalletService(isStandInSession: true);

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    expect(find.text('Not set up'), findsOneWidget);
    expect(_standInRowInk(tester).onTap, isNotNull);
  });

  testWidgets('stand-in session with a nested stand-in reads "Set up"',
      (tester) async {
    final ws = FakeWalletService(
      isStandInSession: true,
      standInConfigured: true,
    );

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    expect(find.text('Set up'), findsOneWidget);
    expect(_standInRowInk(tester).onTap, isNotNull);
  });

  testWidgets('tapping the row opens the stand-in wizard', (tester) async {
    final ws = FakeWalletService();

    await tester.pumpWidget(_app(ws));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stand-in Wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Stand-in Screen'), findsOneWidget);
  });
}
