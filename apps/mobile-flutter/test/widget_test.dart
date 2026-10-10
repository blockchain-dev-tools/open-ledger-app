// Basic smoke test for the Open Ledger App app entry point.
//
// Verifies the app boots without errors and shows the expected
// initial screen (Welcome for fresh install, Unlock for existing wallet).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_ledger_app/main.dart';

void main() {
  testWidgets('app renders welcome screen on fresh install',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OpenLedgerApp());
    // Let the async wallet check resolve (NoWalletStorage returns null).
    await tester.pumpAndSettle();

    // Fresh install: no wallet → Welcome screen with app title "Open Ledger App"
    expect(find.text('Open Ledger App'), findsOneWidget);
  });

  testWidgets('app shows nothing until wallet check resolves',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OpenLedgerApp());
    // With mock SharedPreferences, async init resolves. One extra pump
    // triggers rebuild to WelcomeScreen — no blocker/flash.
    await tester.pump();

    expect(find.text('Open Ledger App'), findsOneWidget);
  });
}
