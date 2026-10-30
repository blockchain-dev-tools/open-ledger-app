// Widget tests for [ImportMnemonicScreen] — 12/24-word acceptance, BIP-39
// prefix suggestions, and QR-scan filling.
//
// The camera is never opened: [ImportMnemonicScreen.qrScanOverride] supplies
// the payload, and validation goes through a fake crypto service (no Rust).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/services/mnemonic_service.dart';
import 'package:open_ledger_app/ui/screens/import_mnemonic/components/mnemonic_suggestions.dart';
import 'package:open_ledger_app/ui/screens/import_mnemonic/import_mnemonic_screen.dart';

import '../support/fake_crypto_service.dart';

const String _phrase12 =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon art';

/// BIP-39 test vector for 256-bit all-zero entropy (valid 24 words).
const String _phrase24 =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon art';

/// Accepts both supported BIP-39 lengths (checksum verification is Rust-owned
/// and exercised elsewhere).
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

Widget _app({Future<String?> Function()? scan, bool addVault = false}) => MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImportMnemonicScreen(
        mnemonicService: MnemonicService(crypto: const _ValidatingCrypto()),
        addVault: addVault,
        qrScanOverride: scan,
      ),
    );

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('mnemonic-input')))
    .controller!
    .text;

void main() {
  testWidgets('typing a prefix shows at most five alphabetical suggestions',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mnemonic-input')), 'a');
    await tester.pump();

    for (final word in ['abandon', 'ability', 'able', 'about', 'above']) {
      expect(find.byKey(MnemonicSuggestions.keyFor(word)), findsOneWidget);
    }
    // The sixth alphabetical match is not rendered.
    expect(find.byKey(MnemonicSuggestions.keyFor('absent')), findsNothing);
  });

  testWidgets('tapping a suggestion completes the word and adds a space',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mnemonic-input')), 'aban');
    await tester.pump();
    await tester.tap(find.byKey(MnemonicSuggestions.keyFor('abandon')));
    await tester.pumpAndSettle();

    expect(_fieldText(tester), 'abandon ');
    final controller =
        tester.widget<TextField>(find.byKey(const Key('mnemonic-input'))).controller!;
    expect(controller.selection.baseOffset, 'abandon '.length);

    // The current word is complete, so the strip disappears.
    expect(find.byKey(MnemonicSuggestions.keyFor('abandon')), findsNothing);
  });

  testWidgets('suggestions disappear once the word ends with a space',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mnemonic-input')), 'aban');
    await tester.pump();
    expect(find.byKey(MnemonicSuggestions.keyFor('abandon')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mnemonic-input')), 'aban ');
    await tester.pump();
    expect(find.byKey(MnemonicSuggestions.keyFor('abandon')), findsNothing);
  });

  testWidgets('a 12-word phrase still validates', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mnemonic-input')), _phrase12);
    await tester.pump();

    expect(find.text('12 / 12 words'), findsOneWidget);
    expect(find.text('Valid recovery phrase'), findsOneWidget);
  });

  testWidgets('a 24-word phrase validates against the 24-word target',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mnemonic-input')), _phrase24);
    await tester.pump();

    expect(find.text('24 / 24 words'), findsOneWidget);
    expect(find.text('Valid recovery phrase'), findsOneWidget);
  });

  testWidgets('a partial 24-word phrase counts towards 24', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('mnemonic-input')),
      _phrase24.split(' ').take(13).join(' '),
    );
    await tester.pump();

    expect(find.text('13 / 24 words'), findsOneWidget);
    expect(find.text('Invalid recovery phrase'), findsOneWidget);
  });

  testWidgets('a scanned 24-word QR fills the field and validates',
      (tester) async {
    await tester.pumpWidget(
      _app(scan: () async => '  ${_phrase24.toUpperCase()}  '),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qr-scan-btn')));
    await tester.pumpAndSettle();

    expect(_fieldText(tester), _phrase24);
    expect(find.text('24 / 24 words'), findsOneWidget);
    expect(find.text('Valid recovery phrase'), findsOneWidget);
  });

  testWidgets('a QR without a usable phrase shows an error and leaves input alone',
      (tester) async {
    await tester.pumpWidget(_app(scan: () async => 'https://example.com'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qr-scan-btn')));
    await tester.pumpAndSettle();

    expect(_fieldText(tester), '');
    expect(
      find.text('This QR code does not contain a 12- or 24-word recovery phrase.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the scanner leaves the input alone', (tester) async {
    await tester.pumpWidget(_app(scan: () async => null));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qr-scan-btn')));
    await tester.pumpAndSettle();

    expect(_fieldText(tester), '');
    expect(find.text('Invalid recovery phrase'), findsNothing);
  });

  testWidgets('first-run import offers no secret-phrase tab', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.byKey(const Key('add-vault-tab-secret')), findsNothing);
    expect(find.byKey(const Key('add-vault-tab-import')), findsNothing);
  });

  testWidgets('new-vault mode tabs the mode at the top and titles the bar',
      (tester) async {
    await tester.pumpWidget(_app(addVault: true));
    await tester.pumpAndSettle();

    // "New Vault" lives in the app bar, not in the scrollable body.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('New Vault')),
      findsOneWidget,
    );
    expect(find.text('Import Wallet'), findsNothing);

    expect(find.byKey(const Key('add-vault-tab-import')), findsOneWidget);
    expect(find.byKey(const Key('add-vault-tab-secret')), findsOneWidget);
    expect(find.text('Import phrase'), findsOneWidget);
    expect(find.text('Secret phrase'), findsOneWidget);
  });

  testWidgets('the secret-phrase tab swaps the form in place',
      (tester) async {
    await tester.pumpWidget(_app(addVault: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-vault-tab-secret')));
    await tester.pumpAndSettle();

    // Same page, same route: the pane under the tabs is the riddle + secret
    // form, not a pushed screen.
    expect(find.byType(ImportMnemonicScreen), findsOneWidget);
    expect(find.byKey(const Key('enigma-riddle')), findsOneWidget);
    expect(find.byKey(const Key('enigma-secret')), findsOneWidget);
    expect(find.byKey(const Key('mnemonic-input')), findsNothing);

    await tester.tap(find.byKey(const Key('add-vault-tab-import')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mnemonic-input')), findsOneWidget);
    expect(find.byKey(const Key('enigma-riddle')), findsNothing);
  });
}
