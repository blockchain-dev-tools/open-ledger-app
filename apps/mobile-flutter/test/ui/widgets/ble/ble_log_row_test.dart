import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger_app/core/models/ble_log_entry.dart';
import 'package:open_ledger_app/ui/widgets/ble/ble_log_row.dart';
import 'package:open_ledger_app/ui/theme/color_tokens.dart';

void main() {
  group('BleLogRow', () {
    testWidgets('expandable row: detail hidden until tapped, toggles on tap',
        (t) async {
      const summary = "APDU command received: GET_PUBKEY path=44'/60'/0'/0/0";
      const detail = 'APDU command received: E0 02 00 00 15 05 80 00 00 2C';
      const entry = BleLogEntry(
        summary: summary,
        detail: detail,
        level: BleLogLevel.info,
        status: BleLogStatus.idle,
        raw: detail,
      );

      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: BleLogRow(entry: entry, c: ColorTokens.dark)),
      ));

      // Summary always visible.
      expect(find.text(summary), findsOneWidget);
      // Detail hidden initially.
      expect(find.text(detail), findsNothing);

      // Tap to expand → detail appears.
      await t.tap(find.byType(BleLogRow));
      await t.pumpAndSettle();
      expect(find.text(detail), findsOneWidget);

      // Tap again to collapse → detail hidden.
      await t.tap(find.byType(BleLogRow));
      await t.pumpAndSettle();
      expect(find.text(detail), findsNothing);
    });

    testWidgets('non-expandable row: shows only summary, no chevron',
        (t) async {
      const entry = BleLogEntry(
        summary: 'BLE state → connected',
        detail: null,
        level: BleLogLevel.info,
        status: BleLogStatus.idle,
        raw: 'BLE state → connected',
      );

      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: BleLogRow(entry: entry, c: ColorTokens.dark)),
      ));

      expect(find.text('BLE state → connected'), findsOneWidget);
      // No expand/collapse icon for plain lines.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('pending row: spinner + request summary, detail stays hidden',
        (t) async {
      const summary = "SOL_GET_ADDR path=44'/501'/0'/0'  →  …";
      const detail =
          'IN  E0 05 00 00 11 04 80 00 00 2C 80 00 01 F5 80 00 00 00 80 00 00 00';
      const entry = BleLogEntry(
        summary: summary,
        detail: detail,
        level: BleLogLevel.info,
        status: BleLogStatus.pending,
        raw: 'APDU command received: E0 05 00 00 11 04 80 00 00 2C',
      );

      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: BleLogRow(entry: entry, c: ColorTokens.dark)),
      ));

      expect(find.text(summary), findsOneWidget);
      // A spinner (CircularProgressIndicator) indicates the in-flight state.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // While pending, the request/response hex stays hidden and there is
      // no expand/collapse chevron.
      expect(find.text(detail), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });
  });
}
