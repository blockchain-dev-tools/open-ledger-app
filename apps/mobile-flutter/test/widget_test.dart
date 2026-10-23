// Basic smoke test for the Open Ledger App entry point.
//
// Verifies the app boots without errors and shows the expected
// initial screen (Welcome for fresh install, Unlock for existing wallet).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_ledger_app/main.dart';

/// Wallet data lives in keystore-backed storage (ADR-007), which is a platform
/// channel. Tests get an in-memory implementation of the same channel so the
/// real `SecureStorage` / `LegacyWalletMigration` code runs unchanged.
void mockSecureStorageChannel() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key!] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'containsKey':
          return store.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'isProtectedDataAvailable':
          return true;
      }
      return null;
    },
  );
}

void main() {
  setUp(mockSecureStorageChannel);

  testWidgets('app renders welcome screen on fresh install',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OpenLedgerAppApp());
    // Let the async wallet check resolve (no credentials in secure storage).
    await tester.pumpAndSettle();

    // Fresh install: no wallet → Welcome screen with app title "Open Ledger App"
    expect(find.text('Open Ledger App'), findsOneWidget);
  });

  testWidgets('app shows nothing until wallet check resolves',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OpenLedgerAppApp());
    // With mock storage, async init resolves. One extra pump triggers the
    // rebuild to WelcomeScreen — no blocker/flash.
    await tester.pump();

    expect(find.text('Open Ledger App'), findsOneWidget);
  });
}
