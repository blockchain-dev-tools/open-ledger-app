/// Widget tests for [BackupSeedScreen] — the PIN-gated seed reveal
/// (contract I6).
///
/// T-003 coverage: the screen displays the **global persisted** attempt
/// counter shared with the unlock gate (never a screen-local count), the
/// lockout view derives from that truth, and the revealed words come from
/// `IWalletService.revealMnemonic` — no demo words.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/wallet_service.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/backup_seed/backup_seed_screen.dart';

const _correctPin = '123456';

/// A real BIP-39 vector distinct from the retired demo list, so the test
/// proves the words come from [IWalletService.revealMnemonic].
const _seedWords =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';

const _lockedHint =
    'The wallet is permanently locked. Go back and reset your wallet to continue.';

/// Minimal wallet view: only the members the screen reads. Failures
/// increment / success resets the counter, mirroring the global side
/// effects of `PinBiz.matchCredential`.
class _FakeWallet implements IWalletService {
  _FakeWallet({this.attempts = 0});

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
      pin == _correctPin ? _seedWords : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<void> _pumpScreen(
  WidgetTester tester,
  IWalletService? walletService,
) async {
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
      home: BackupSeedScreen(walletService: walletService),
    ),
  );
}

/// Types [pin] on the screen's pad, then lets the async verify and the
/// 400 ms shake timer run.
Future<void> _enter(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('backup-seed-btn-$digit')));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('starts on the PIN phase with the seed hidden', (tester) async {
    await _pumpScreen(tester, _FakeWallet());

    expect(find.text('Enter PIN'), findsOneWidget);
    expect(find.text('Your Seed Phrase'), findsNothing);
  });

  testWidgets('without a wallet service nothing is revealed (gallery)',
      (tester) async {
    await _pumpScreen(tester, null);
    await _enter(tester, _correctPin);

    expect(find.text('Your Seed Phrase'), findsNothing);
    expect(find.textContaining('winner'), findsNothing);
  });

  testWidgets('the correct PIN reveals the real mnemonic', (tester) async {
    await _pumpScreen(tester, _FakeWallet());
    await _enter(tester, _correctPin);

    // Words come from the service (numbered cells, "N. word"), not a demo list.
    expect(find.textContaining('winner'), findsWidgets);
    expect(find.textContaining('abandon'), findsNothing);
  });

  testWidgets('a wrong PIN stays hidden and consumes an attempt',
      (tester) async {
    await _pumpScreen(tester, _FakeWallet());
    await _enter(tester, '999999');

    expect(find.text('Your Seed Phrase'), findsNothing);
    expect(find.text('Attempts remaining: 4/5'), findsOneWidget);
  });

  testWidgets('five wrong PINs lock the gate out with the reset hint',
      (tester) async {
    await _pumpScreen(tester, _FakeWallet());

    for (var i = 0; i < 5; i++) {
      await _enter(tester, '999999');
    }

    expect(find.text('Locked out'), findsWidgets);
    // No "try again later" — the lock is permanent (T-003).
    expect(find.text(_lockedHint), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-seed-btn-1')), findsNothing);
  });

  testWidgets('a screen whose counter is already at max starts locked out',
      (tester) async {
    // The wallet was locked elsewhere (e.g. the unlock gate) while this
    // session was open — the gate must reflect it before any input.
    await _pumpScreen(tester, _FakeWallet(attempts: 5));

    expect(find.text('Locked out'), findsWidgets);
    expect(find.text(_lockedHint), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-seed-btn-1')), findsNothing);
  });

  testWidgets('the counter is the shared truth: it survives a rebuild',
      (tester) async {
    final wallet = _FakeWallet();

    await _pumpScreen(tester, wallet);
    await _enter(tester, '999999');
    await _enter(tester, '999999');
    expect(find.text('Attempts remaining: 3/5'), findsOneWidget);

    // A fresh screen (page re-entry, app restart) picks the counter up
    // from the service — no screen-local reset to 5/5.
    await _pumpScreen(tester, wallet);
    expect(find.text('Attempts remaining: 3/5'), findsOneWidget);
  });
}
