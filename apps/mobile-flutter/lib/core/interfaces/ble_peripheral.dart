import 'dart:async';
import 'dart:typed_data';

import '../models/ble_types.dart';

/// Contract for the BLE GATT server peripheral (Ledger Nano X-compatible).
///
/// `AppState`, `BleSession`, and the BLE tab depend on this interface, never
/// on the concrete implementation in `infrastructure/ble/`. This keeps the
/// app/biz layers compilable for Flutter web (design gallery) and lets tests
/// substitute a hand-written mock without triggering constructor
/// side-effects of the real peripheral.
abstract class IBlePeripheral {
  /// Current BLE state-machine state.
  BleState get state;

  /// Stream of complete, reassembled APDU commands from the connected
  /// central.
  Stream<Uint8List> get apduStream;

  /// Stream of BLE state transitions.
  Stream<BleState> get stateStream;

  /// Human-readable activity log (advertising, GATT reads/writes, errors).
  Stream<String> get logStream;

  /// The advertised local device name.
  String get deviceName;

  /// Negotiated MTU in bytes.
  int get mtu;

  /// Register the GATT service and start advertising.
  Future<void> startAdvertising();

  /// Stop advertising and clear registered services.
  Future<void> stopAdvertising();

  /// Set the advertised local device name (takes effect on next advertise).
  Future<void> setDeviceName(String name);

  /// Fragment and send an APDU response to the connected central.
  Future<void> sendApduResponse(Uint8List response);

  /// Release all resources (stream controllers, platform handlers).
  void dispose();
}
