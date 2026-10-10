// Widget tests for [TxDetailsCard] — the shared decoded-transaction card used
// by both the sign-approval screen and the History expanded row.
//
// Regression: the card must render the Solana summary (To / Amount / Program /
// Type) and fall back to raw hex + size when the payload could not be decoded.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/theme/color_tokens.dart';
import 'package:open_ledger_app/ui/widgets/tx_details_card.dart';

Widget _app({Map<String, dynamic>? parsed, String payloadHex = 'dead'}) {
  return MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TxDetailsCard(
        parsedData: parsed,
        payloadHex: payloadHex,
        c: ColorTokens.dark,
      ),
    ),
  );
}

void main() {
  testWidgets('renders the Solana transfer summary', (tester) async {
    await tester.pumpWidget(_app(parsed: {
      'type': 'solana_tx',
      'chain': 'solana',
      'version': 'legacy',
      'feePayer': '7Z1b92qmpkuMxqXyYLZgbmTToxzq2jZ7J83oVZ12rPbY',
      'to': '7Z1b92qmpkuMxqXyYLZgbmTToxzq2jZ7J83oVZ12rPbY',
      'programId': '11111111111111111111111111111111',
      'action': 'transfer',
      'lamports': '10000',
      'instructionCount': 1,
    }));
    await tester.pumpAndSettle();

    expect(find.text('To'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('0.00001 SOL'), findsOneWidget);
    expect(find.text('Program'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('legacy'), findsOneWidget);
  });

  testWidgets('falls back to raw hex + size when nothing was decoded',
      (tester) async {
    await tester.pumpWidget(_app(parsed: null, payloadHex: 'abcd'));
    await tester.pumpAndSettle();

    expect(find.text('Data hex'), findsOneWidget);
    expect(find.text('0xabcd'), findsOneWidget);
    expect(find.text('Data size'), findsOneWidget);
    expect(find.text('2 bytes'), findsOneWidget);
  });
}
