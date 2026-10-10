/// Widget tests for the three backup-verification screens (ADR-011 §5).
///
/// The verifier is faked at the `core/interfaces/` boundary (never a concrete
/// class), so each screen is exercised for its verdict rendering
/// (match / mismatch / unavailable), its input plumbing, and the preview mode
/// the design gallery relies on. No crypto, storage or FFI is involved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/backup_verifier.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/screens/seed_export/backup_export_screen.dart';
import 'package:open_ledger_app/ui/screens/verify/verify_backup_enigma_screen.dart';
import 'package:open_ledger_app/ui/screens/verify/verify_backup_mnemonic_screen.dart';
import 'package:open_ledger_app/ui/screens/verify/verify_backup_passphrase_screen.dart';
import 'package:open_ledger_app/ui/widgets/verify/verify_result_card.dart';

/// Records the inputs it is handed and returns a scripted verdict.
class _FakeVerifier implements IBackupVerifier {
  _FakeVerifier({
    this.result = VerifyResult.match,
    this.isEnigma = false,
  });

  VerifyResult result;

  @override
  bool isEnigma;

  @override
  bool hasPassphrase = false;

  String? lastMnemonic;
  String? lastPassphrase;
  ({String riddle, String secret})? lastEnigma;

  @override
  Future<VerifyResult> verifyMnemonic(String mnemonic) async {
    lastMnemonic = mnemonic;
    return result;
  }

  @override
  Future<VerifyResult> verifyPassphrase(String passphrase) async {
    lastPassphrase = passphrase;
    return result;
  }

  @override
  Future<VerifyResult> verifyEnigma(String riddle, String secret) async {
    lastEnigma = (riddle: riddle, secret: secret);
    return result;
  }
}

Widget _wrap(Widget child) => MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

void main() {
  group('VerifyBackupMnemonicScreen', () {
    testWidgets('shows a match verdict for the retyped phrase', (tester) async {
      final verifier = _FakeVerifier(result: VerifyResult.match);
      await tester.pumpWidget(
        _wrap(VerifyBackupMnemonicScreen(verifier: verifier)),
      );

      await tester.enterText(
        find.byKey(const Key('verify-seed-input')),
        'abandon abandon about',
      );
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verifier.lastMnemonic, 'abandon abandon about');
      expect(find.byType(VerifyResultCard), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('shows a mismatch verdict', (tester) async {
      final verifier = _FakeVerifier(result: VerifyResult.mismatch);
      await tester.pumpWidget(
        _wrap(VerifyBackupMnemonicScreen(verifier: verifier)),
      );

      await tester.enterText(
        find.byKey(const Key('verify-seed-input')),
        'wrong words',
      );
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows the unavailable verdict distinctly', (tester) async {
      final verifier = _FakeVerifier(result: VerifyResult.unavailable);
      await tester.pumpWidget(
        _wrap(VerifyBackupMnemonicScreen(verifier: verifier)),
      );

      await tester.enterText(
        find.byKey(const Key('verify-seed-input')),
        'abandon abandon about',
      );
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      // `unavailable` must not read as a user error.
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('does not verify while the input is empty', (tester) async {
      final verifier = _FakeVerifier();
      await tester.pumpWidget(
        _wrap(VerifyBackupMnemonicScreen(verifier: verifier)),
      );

      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verifier.lastMnemonic, isNull);
      expect(find.byType(VerifyResultCard), findsNothing);
    });

    testWidgets('preview mode renders the frozen verdict without a verifier',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const VerifyBackupMnemonicScreen(
            previewInput: 'abandon abandon about',
            previewResult: VerifyResult.match,
          ),
        ),
      );

      expect(find.byType(VerifyResultCard), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('VerifyBackupPassphraseScreen', () {
    testWidgets('passes the typed passphrase to the verifier', (tester) async {
      final verifier = _FakeVerifier(result: VerifyResult.match);
      await tester.pumpWidget(
        _wrap(VerifyBackupPassphraseScreen(verifier: verifier)),
      );

      await tester.enterText(
        find.byKey(const Key('verify-passphrase-input')),
        'my secret pass',
      );
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verifier.lastPassphrase, 'my secret pass');
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('obscures the input until the eye is tapped', (tester) async {
      await tester.pumpWidget(
        _wrap(VerifyBackupPassphraseScreen(verifier: _FakeVerifier())),
      );

      TextField field() =>
          tester.widget<TextField>(find.byKey(const Key('verify-passphrase-input')));
      expect(field().obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      expect(field().obscureText, isFalse);
    });

    testWidgets('shows a mismatch verdict', (tester) async {
      final verifier = _FakeVerifier(result: VerifyResult.mismatch);
      await tester.pumpWidget(
        _wrap(VerifyBackupPassphraseScreen(verifier: verifier)),
      );

      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verifier.lastPassphrase, '');
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('VerifyBackupEnigmaScreen', () {
    testWidgets('passes both riddle and secret to the verifier',
        (tester) async {
      final verifier = _FakeVerifier(result: VerifyResult.match);
      await tester.pumpWidget(
        _wrap(VerifyBackupEnigmaScreen(verifier: verifier)),
      );

      await tester.enterText(
        find.byKey(const Key('verify-enigma-riddle')),
        'a riddle',
      );
      await tester.enterText(
        find.byKey(const Key('verify-enigma-secret')),
        'a key',
      );
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(verifier.lastEnigma?.riddle, 'a riddle');
      expect(verifier.lastEnigma?.secret, 'a key');
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('shows the unavailable verdict', (tester) async {
      final verifier = _FakeVerifier(result: VerifyResult.unavailable);
      await tester.pumpWidget(
        _wrap(VerifyBackupEnigmaScreen(verifier: verifier)),
      );

      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });
  });

  group('BackupExportScreen verification rows', () {
    testWidgets('always offers the phrase and passphrase checks',
        (tester) async {
      await tester.pumpWidget(
        _wrap(BackupExportScreen(backupVerifier: _FakeVerifier())),
      );

      expect(find.text('Verify Recovery Phrase'), findsOneWidget);
      expect(find.text('Verify Passphrase'), findsOneWidget);
      // A non-Enigma vault must not advertise the riddle path.
      expect(find.text('Verify Secret Phrase'), findsNothing);
    });

    testWidgets('adds the riddle row only for an Enigma vault', (tester) async {
      await tester.pumpWidget(
        _wrap(
          BackupExportScreen(backupVerifier: _FakeVerifier(isEnigma: true)),
        ),
      );

      expect(find.text('Verify Secret Phrase'), findsOneWidget);
    });

    testWidgets('preview mode honours the isEnigma flag', (tester) async {
      await tester.pumpWidget(
        _wrap(const BackupExportScreen(isEnigma: true)),
      );

      expect(find.text('Verify Secret Phrase'), findsOneWidget);
    });
  });
}
