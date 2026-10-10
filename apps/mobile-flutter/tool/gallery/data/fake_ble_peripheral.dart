import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:open_ledger_app/core/interfaces/ble_peripheral.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';

/// Gallery fake for [IBlePeripheral] (ADR-005).
///
/// Starts in [BleState.broadcasting] with a realistic backlog of log lines
/// (advertising → connect → MTU → one GET_PUBKEY exchange), so the Vault
/// chain controls and the BLE log sheet render their informative states
/// without a real radio. Starting/stopping switches between broadcasting
/// and idle.
///
/// Extends [ChangeNotifier] because the Vault controls rebuild from the
/// chain-BLE control's listenable — in the gallery there is no AppState, so
/// the fake itself drives rebuilds.
class FakeBlePeripheral extends ChangeNotifier implements IBlePeripheral {
  BleState _state;

  FakeBlePeripheral({BleState initialState = BleState.broadcasting})
      : _state = initialState {
    if (initialState == BleState.broadcasting ||
        initialState == BleState.connected) {
      // A realistic GET_PUBKEY exchange for m/44'/60'/0'/0/0.
      // Command: CLA=e0 INS=02 P1=00 P2=00 Lc=15 — data = count(05) +
      // 5×uint32 BE path segments (44' 60' 0' 0 0).
      //
      // The response uses BlePeripheralUniversal's exact `APDU response:`
      // format so ApduLogDecoder resolves the pending command row in place.
      // (The old `sending`/`sent` pair matched no branch, leaving a spinner
      // row stuck forever.)
      // Synthetic locally administered MAC for gallery data; no real device.
      _backlog.addAll(const [
        'Advertising state: broadcasting',
        'Device 02:00:00:00:00:01 connected',
        'MTU changed: 247',
        'APDU command received: e002000015058000002c8000003c800000000000000000000000',
        'APDU response: 4104a3f5c2e1b7d8901234abcdef5678901234abcdef5678901234abcdef5678901234567890abcdef1234567890abcdef12345678909000',
      ]);
    }
  }

  final List<String> _backlog = [];
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _apduController =
      StreamController<Uint8List>.broadcast();
  final StreamController<BleState> _stateController =
      StreamController<BleState>.broadcast();

  @override
  BleState get state => _state;

  @override
  String get deviceName => 'OpenLedgerAppApp';

  @override
  int get mtu => 247;

  /// Replays the canned backlog to late subscribers, then live lines.
  @override
  Stream<String> get logStream async* {
    for (final line in _backlog) {
      yield line;
    }
    yield* _logController.stream;
  }

  @override
  Stream<Uint8List> get apduStream => _apduController.stream;

  @override
  Stream<BleState> get stateStream => _stateController.stream;

  void _log(String line) {
    _backlog.add(line);
    _logController.add(line);
  }

  /// Gallery hook: append a synthetic activity line (e.g. an app switch).
  void emitLog(String line) => _log(line);

  void _setState(BleState next) {
    _state = next;
    _stateController.add(next);
    notifyListeners();
  }

  @override
  Future<void> startAdvertising() async {
    _log('Advertising state: broadcasting');
    _setState(BleState.broadcasting);
  }

  @override
  Future<void> stopAdvertising() async {
    _log('BLE advertising stopped.');
    _setState(BleState.idle);
  }

  @override
  Future<void> setDeviceName(String name) async {
    _log('Device name set to "$name".');
  }

  @override
  Future<void> sendApduResponse(Uint8List response) async {
    final hex =
        response.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _log('APDU response: $hex');
  }

  @override
  void dispose() {
    _logController.close();
    _apduController.close();
    _stateController.close();
    super.dispose();
  }
}
