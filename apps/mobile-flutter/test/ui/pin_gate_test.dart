/// Widget tests for [PinGate] — the on-the-spot PIN re-verification that
/// guards every secret-bearing export screen (contract I6, ADR-011 §6).
///
/// T-003: the gate displays the **global persisted** attempt counter shared
/// with the unlock gate — never a screen-local count — and the lockout view
/// derives from that truth.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/export_service.dart';
import 'package:open_ledger_app/core/models/wallet_accounts.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/widgets/pin/pin_gate.dart';

const _correctPin = '123456';
const _lockedHint =
    'The wallet is permanently locked. Go back and reset your wallet to continue.';

/// Only the session-PIN surface matters here; the secrets themselves are
/// covered by the export-service tests.
///
/// The counter mimics `PinBiz.matchCredential`'s global side effects:
/// failures increment, success resets — so the gate's display and lockout
/// are exercised against the same truth the app ships with.
class _FakeExport implements IExportService {
  _FakeExport({this.attempts = 0});

  int attempts = 0;

  @override
  int get pinAttempts => attempts;

  @override
  int get maxPinAttempts => 5;

  @override
  Future<bool> verifySessionPin(String pin) async {
    if (pin == _correctPin) {
      attempts = 0;
      return true;
    }
    attempts++;
    return false;
  }

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

Future<void> _pumpGate(
  WidgetTester tester,
  _FakeExport export, {
  VoidCallback? onLockedOut,
}) async {
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
            exportService: export,
            keyPrefix: 'test',
            onLockedOut: onLockedOut,
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
    await _pumpGate(tester, _FakeExport());

    expect(find.text('Enter PIN'), findsOneWidget);
    expect(find.text('REVEALED'), findsNothing);
  });

  testWidgets('the correct PIN reveals the secret', (tester) async {
    await _pumpGate(tester, _FakeExport());
    await _enter(tester, _correctPin);

    expect(find.text('REVEALED'), findsOneWidget);
    // The pad is gone once the secret is shown.
    expect(find.byKey(const ValueKey('test-btn-1')), findsNothing);
  });

  testWidgets('a wrong PIN stays hidden and consumes an attempt',
      (tester) async {
    await _pumpGate(tester, _FakeExport());
    await _enter(tester, '999999');

    expect(find.text('REVEALED'), findsNothing);
    expect(find.text('Attempts remaining: 4/5'), findsOneWidget);
    // The entry is cleared for the next try.
    expect(find.text('Incorrect PIN'), findsNothing);
  });

  testWidgets('five wrong PINs lock the gate out with the reset hint',
      (tester) async {
    await _pumpGate(tester, _FakeExport());

    for (var i = 0; i < 5; i++) {
      await _enter(tester, '999999');
    }

    expect(find.text('REVEALED'), findsNothing);
    expect(find.text('Locked out'), findsWidgets);
    // No "try again later" — the lock is permanent (T-003).
    expect(find.text(_lockedHint), findsOneWidget);
    // The pad is replaced by the lockout explanation.
    expect(find.byKey(const ValueKey('test-btn-1')), findsNothing);
  });

  testWidgets('the counter is the shared truth: it survives a rebuild',
      (tester) async {
    final export = _FakeExport();

    await _pumpGate(tester, export);
    await _enter(tester, '999999');
    await _enter(tester, '999999');
    expect(find.text('Attempts remaining: 3/5'), findsOneWidget);

    // A fresh gate (page re-entry, app restart) picks the counter up from
    // the service — no screen-local reset to 5/5.
    await _pumpGate(tester, export);
    expect(find.text('Attempts remaining: 3/5'), findsOneWidget);
  });

  testWidgets('a gate whose counter is already at max starts locked out',
      (tester) async {
    // The wallet was locked elsewhere (e.g. the unlock gate) while this
    // session was open — the gate must reflect it before any input.
    await _pumpGate(tester, _FakeExport(attempts: 5));

    expect(find.text('Locked out'), findsWidgets);
    expect(find.text(_lockedHint), findsOneWidget);
    expect(find.byKey(const ValueKey('test-btn-1')), findsNothing);
  });

  testWidgets('an already locked-out gate reports the lockout on entry',
      (tester) async {
    var reported = 0;
    await _pumpGate(tester, _FakeExport(attempts: 5),
        onLockedOut: () => reported++);
    await tester.pump();

    // The host screen is told right away, so it can leave this route for the
    // unlock screen's reset exit instead of showing a dead pad.
    expect(reported, 1);
  });

  testWidgets('the failure that exhausts the counter reports the lockout',
      (tester) async {
    var reported = 0;
    await _pumpGate(tester, _FakeExport(), onLockedOut: () => reported++);

    for (var i = 0; i < 5; i++) {
      await _enter(tester, '999999');
    }

    expect(reported, 1);
  });
}
