// Widget tests for the floating BLE control: chain-picker start, hot
// switch, stop, and the sign-pending disabled guard.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/ble_peripheral.dart';
import 'package:open_ledger_app/core/interfaces/chain_ble_control.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/core/models/chain.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/widgets/ble/ble_control_sheet.dart';
import 'package:open_ledger_app/ui/widgets/ble/ble_fab.dart';
import 'package:open_ledger_app/ui/widgets/ble/ble_log_controller.dart';

/// Minimal peripheral — the log sheet only needs an empty log stream.
class _FakeBlePeripheral implements IBlePeripheral {
  @override
  BleState get state => BleState.idle;
  @override
  Stream<Uint8List> get apduStream => const Stream.empty();
  @override
  Stream<BleState> get stateStream => const Stream.empty();
  @override
  Stream<String> get logStream => const Stream.empty();
  @override
  String get deviceName => 'TestDevice';
  @override
  int get mtu => 517;
  @override
  Future<void> startAdvertising() async {}
  @override
  Future<void> stopAdvertising() async {}
  @override
  Future<void> setDeviceName(String name) async {}
  @override
  Future<void> sendApduResponse(Uint8List response) async {}
  @override
  void dispose() {}
}

class _FakeBleControl extends ChangeNotifier implements IChainBleControl {
  BleState state = BleState.idle;
  Chain? chain;
  bool pending = false;
  final List<Chain> starts = [];
  int stops = 0;

  @override
  BleState get bleState => state;
  @override
  Chain? get activeChain => chain;
  @override
  bool get isSignPending => pending;

  @override
  Future<void> startChain(Chain c) async {
    starts.add(c);
    chain = c;
    state = BleState.broadcasting;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
    chain = null;
    state = BleState.idle;
    notifyListeners();
  }
}

Widget _app(
  _FakeBleControl control, {
  BleLogController? logController,
  List<Chain> chains = Chain.withLedgerApp,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      floatingActionButton: BleFab(
        control: control,
        onTap: () => BleControlSheet.open(
          _navigatorKey.currentContext!,
          control: control,
          chains: chains,
          logController: logController,
        ),
      ),
    ),
    navigatorKey: _navigatorKey,
  );
}

final _navigatorKey = GlobalKey<NavigatorState>();

void main() {
  testWidgets('idle: FAB opens the emulated-app picker; tapping one starts BLE',
      (tester) async {
    final control = _FakeBleControl();
    await tester.pumpWidget(_app(control));
    await tester.pump();

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    for (final label in const [
      'Bitcoin',
      'Ethereum',
      'Solana',
      'Tron',
      'Sui',
      'NEAR',
      'TON',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    // Every chain has an emulated Rust app; with all of them passed in, the
    // picker offers each one.
    expect(find.byKey(const ValueKey('ble-chain-near')), findsOneWidget);
    expect(find.byKey(const ValueKey('ble-chain-ton')), findsOneWidget);

    await tester.tap(find.text('Ethereum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(control.starts, [Chain.ethereum]);
    expect(control.stops, 0);
    // Starting from idle leaves the sheet open so the flip to broadcasting
    // is visible — the tile now carries the stop affordance.
    expect(find.text('Tron'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.text('Tap the active chain again to stop broadcasting.'),
        findsOneWidget);
  });

  testWidgets('picker offers only the chains the vault shows', (tester) async {
    final control = _FakeBleControl();
    // A vault where the user has not added Sui/NEAR/TON yet.
    await tester.pumpWidget(_app(control, chains: Chain.defaultVisible));
    await tester.pump();

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    for (final chain in Chain.defaultVisible) {
      expect(find.byKey(ValueKey('ble-chain-${chain.id}')), findsOneWidget);
    }
    for (final chain in Chain.addable) {
      expect(find.byKey(ValueKey('ble-chain-${chain.id}')), findsNothing);
    }
  });

  testWidgets('active: switch to another chain is a hot switch',
      (tester) async {
    final control = _FakeBleControl()
      ..state = BleState.broadcasting
      ..chain = Chain.ethereum;
    await tester.pumpWidget(_app(control));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Solana'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(control.starts, [Chain.solana]);
    expect(control.stops, 0);
    expect(control.activeChain, Chain.solana);
    // Switching does not dismiss the sheet — the tiles update in place.
    expect(find.text('Tron'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('active: tapping the active chain again stops broadcasting',
      (tester) async {
    final control = _FakeBleControl()
      ..state = BleState.connected
      ..chain = Chain.ethereum;
    await tester.pumpWidget(_app(control));
    await tester.pump();

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The active tile carries the stop affordance (power badge) and the
    // hint line that teaches the gesture.
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(find.text('Tap the active chain again to stop broadcasting.'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Stop broadcasting'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(control.stops, 1);
    expect(control.starts, isEmpty);
    expect(control.bleState, BleState.idle);
    // Stopping does not dismiss the sheet either.
    expect(find.text('Tron'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('idle: shows a start hint instead of a stop affordance',
      (tester) async {
    final control = _FakeBleControl();
    await tester.pumpWidget(_app(control));
    await tester.pump();

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(find.text('Tap the active chain again to stop broadcasting.'),
        findsNothing);
    // The hint slot is filled from the very first open — how to start.
    expect(find.text('Tap a chain to start broadcasting.'), findsOneWidget);
  });

  testWidgets('starting or switching flips the sheet to the log view',
      (tester) async {
    final control = _FakeBleControl();
    final logs = BleLogController(_FakeBlePeripheral());
    await tester.pumpWidget(_app(control, logController: logs));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Tron'), findsOneWidget); // control view

    await tester.tap(find.text('Ethereum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(control.starts, [Chain.ethereum]);
    // Landed on the log view (its in-sheet back button) inside one sheet.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Bitcoin'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('sign pending: FAB is inert', (tester) async {
    final control = _FakeBleControl()
      ..state = BleState.broadcasting
      ..chain = Chain.ethereum
      ..pending = true;
    await tester.pumpWidget(_app(control));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // No sheet, no state change.
    expect(find.text('Bitcoin'), findsNothing);
    expect(control.starts, isEmpty);
    expect(control.stops, 0);
  });

  testWidgets('logs are a second view in the same sheet — never a nested sheet',
      (tester) async {
    final control = _FakeBleControl()
      ..state = BleState.broadcasting
      ..chain = Chain.ethereum;
    final logs = BleLogController(_FakeBlePeripheral());
    await tester.pumpWidget(_app(control, logController: logs));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Tron'), findsOneWidget); // control view

    await tester.tap(find.byKey(const Key('ble-sheet-logs')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The page slide is 300ms; give the outgoing view one more frame to be
    // removed before asserting it is gone.
    await tester.pump(const Duration(milliseconds: 50));

    // Logs replace the control view inside the SAME sheet route.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Bitcoin'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget); // no sheet-on-sheet

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('Tron'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('no logs callback: the logs entry is hidden', (tester) async {
    final control = _FakeBleControl();
    await tester.pumpWidget(_app(control));
    await tester.pump();

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('ble-sheet-logs')), findsNothing);
  });

  testWidgets('error state: sheet shows the chain and an error subtitle',
      (tester) async {
    final control = _FakeBleControl()
      ..state = BleState.error
      ..chain = Chain.ethereum;
    await tester.pumpWidget(_app(control));
    await tester.pump();

    await tester.tap(find.byType(BleFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ethereum'), findsWidgets);
    // Regression: the error state used to fall through to the idle
    // "start broadcasting" hint, hiding that something went wrong.
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Start BLE broadcasting to accept signing requests.'),
        findsNothing);
  });

  testWidgets('pending: FAB semantics keep a meaningful label',
      (tester) async {
    final control = _FakeBleControl()
      ..state = BleState.broadcasting
      ..chain = Chain.ethereum
      ..pending = true;
    await tester.pumpWidget(_app(control));
    await tester.pump(const Duration(milliseconds: 300));

    final semantics = tester.getSemantics(find.byType(BleFab));
    expect(semantics.label, contains('Signing request pending'));
  });
}
