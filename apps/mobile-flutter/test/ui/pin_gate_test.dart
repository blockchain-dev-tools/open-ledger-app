/// Widget tests for [PinGate] — the on-the-spot PIN re-verification that
/// guards every secret-bearing export screen (contract I6, ADR-011 §6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/export_service.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/widgets/pin/pin_gate.dart';

const _correctPin = '123456';

/// Only the session-PIN surface matters here; the secrets themselves are
/// covered by the export-service tests.
class _FakeExport implements IExportService {
  @override
  Future<bool> verifySessionPin(String pin) async => pin == _correctPin;

  @override
  Future<String?> revealMnemonic(String pin) async =>
      pin == _correctPin ? 'abandon ability able' : null;

  @override
  bool get hasPassphrase => false;

  @override
  String? get fingerprint => 'c0ffee12';

  @override
  List<ChainAccount> get accounts => const [];

  @override
  String? encodePrivateKey(ChainAccount account) => null;

  @override
  String? encodingLabel(ChainAccount account) => null;
}

Future<void> _pumpGate(WidgetTester tester) async {
  // A tall surface keeps the whole pad hittable without scrolling.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: PinGate(
            exportService: _FakeExport(),
            keyPrefix: 'test',
            onUnlocked: (pin) async => const Text('REVEALED'),
          ),
        ),
      ),
    ),
  );
}

/// Types [pin], then lets the async verify and the 400 ms shake timer run.
Future<void> _enter(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('test-btn-$digit')));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('starts on the PIN phase with the secret hidden', (tester) async {
    await _pumpGate(tester);

    expect(find.text('Enter PIN'), findsOneWidget);
    expect(find.text('REVEALED'), findsNothing);
  });

  testWidgets('the correct PIN reveals the secret', (tester) async {
    await _pumpGate(tester);
    await _enter(tester, _correctPin);

    expect(find.text('REVEALED'), findsOneWidget);
    // The pad is gone once the secret is shown.
    expect(find.byKey(const ValueKey('test-btn-1')), findsNothing);
  });

  testWidgets('a wrong PIN stays hidden and consumes an attempt',
      (tester) async {
    await _pumpGate(tester);
    await _enter(tester, '999999');

    expect(find.text('REVEALED'), findsNothing);
    expect(find.text('Attempts remaining: 4/5'), findsOneWidget);
    // The entry is cleared for the next try.
    expect(find.text('Incorrect PIN'), findsNothing);
  });

  testWidgets('five wrong PINs lock the gate out', (tester) async {
    await _pumpGate(tester);

    for (var i = 0; i < 5; i++) {
      await _enter(tester, '999999');
    }

    expect(find.text('REVEALED'), findsNothing);
    expect(find.text('Locked out'), findsWidgets);
    // The pad is replaced by the lockout explanation.
    expect(find.byKey(const ValueKey('test-btn-1')), findsNothing);
  });
}
