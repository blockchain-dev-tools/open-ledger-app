import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
// `PeripheralService` is the pigeon type used by the platform interface; the
// package's public barrel hides it, so the fake imports it from src.
import 'package:universal_ble/src/universal_ble.g.dart' show PeripheralService;

import 'package:open_ledger_app/core/interfaces/ble_permissions.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/infrastructure/ble/ble_peripheral_universal.dart';

/// Grants every runtime permission the peripheral asks for.
class _GrantedBlePermissions implements IBlePermissions {
  @override
  Future<bool> ensureGranted() async => true;
}

/// Platform stand-in with a switchable advertising state, so a test can claim
/// "the app thinks it is broadcasting but the platform is not".
class _FakePeripheralPlatform extends UniversalBlePeripheralPlatform {
  PeripheralAdvertisingState advertising = PeripheralAdvertisingState.idle;
  PeripheralReadinessState readiness = PeripheralReadinessState.ready;
  final List<String> calls = <String>[];

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async => readiness;

  @override
  Future<PeripheralAdvertisingState> getAdvertisingState() async => advertising;

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async =>
      const BlePeripheralCapabilities(
        supportsPeripheralMode: true,
        supportsManufacturerDataInAdvertisement: true,
        supportsManufacturerDataInScanResponse: true,
        supportsServiceDataInAdvertisement: true,
        supportsServiceDataInScanResponse: true,
        supportsTargetedCharacteristicUpdate: true,
        supportsAdvertisingTimeout: true,
      );

  @override
  Future<void> addService(PeripheralService service, {Duration? timeout}) async {
    calls.add('addService');
  }

  @override
  Future<void> removeService(String serviceId) async {}

  @override
  Future<void> clearServices() async => calls.add('clearServices');

  @override
  Future<List<String>> getServices() async => <String>[bleServiceUuid];

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) async {
    calls.add('startAdvertising');
    advertising = PeripheralAdvertisingState.advertising;
  }

  @override
  Future<void> stopAdvertising() async {
    calls.add('stopAdvertising');
    advertising = PeripheralAdvertisingState.idle;
  }

  @override
  Future<void> updateCharacteristicValue({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) async {}

  @override
  Future<List<String>> getSubscribedClients(String characteristicId) async =>
      <String>[];

  @override
  Future<int?> getMaximumNotifyLength(String deviceId) async => null;

  @override
  void setReadRequestHandler(OnPeripheralReadRequest? handler) {}

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest? handler) {}

  @override
  void setDescriptorReadRequestHandler(
    OnPeripheralDescriptorReadRequest? handler,
  ) {}

  @override
  void setDescriptorWriteRequestHandler(
    OnPeripheralDescriptorWriteRequest? handler,
  ) {}
}

void main() {
  // `dispose()` drives `universal_ble`'s request handlers and streams, which
  // reach `ServicesBinding.instance`; the binding must exist first.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePeripheralPlatform platform;

  setUp(() {
    platform = _FakePeripheralPlatform();
    UniversalBlePeripheral.setInstance(platform);
  });

  BlePeripheralUniversal buildPeripheral({Stream<AvailabilityState>? events}) {
    final peripheral = BlePeripheralUniversal(
      permissions: _GrantedBlePermissions(),
      availabilityStream: events ?? const Stream<AvailabilityState>.empty(),
    );
    addTearDown(peripheral.dispose);
    return peripheral;
  }

  test('a cached broadcasting state does not skip the rebuild when the '
      'platform stopped advertising', () async {
    final peripheral = buildPeripheral();

    await peripheral.startAdvertising();
    expect(peripheral.state, BleState.broadcasting);

    // Bluetooth toggled: the framework advertising set is gone while the app
    // still caches `broadcasting`.
    platform.advertising = PeripheralAdvertisingState.idle;
    platform.calls.clear();

    final logs = <String>[];
    final sub = peripheral.logStream.listen(logs.add);
    addTearDown(sub.cancel);

    await peripheral.startAdvertising();
    await pumpEventQueue();

    expect(
      platform.calls,
      containsAll(<String>['addService', 'startAdvertising']),
      reason: 'the peripheral must rebuild the GATT server and advertising',
    );
    expect(peripheral.state, BleState.broadcasting);
    expect(
      logs.any((line) => line.contains('rebuilding')),
      isTrue,
      reason: 'the reconciliation should be visible in the activity log',
    );
  });

  test('an unchanged broadcasting state still short-circuits', () async {
    final peripheral = buildPeripheral();

    await peripheral.startAdvertising();
    platform.calls.clear();

    await peripheral.startAdvertising();

    expect(platform.calls, isEmpty);
    expect(peripheral.state, BleState.broadcasting);
  });

  test('Bluetooth off then on resumes advertising without user action', () async {
    final availability = StreamController<AvailabilityState>();
    addTearDown(availability.close);
    final peripheral = buildPeripheral(events: availability.stream);

    await peripheral.startAdvertising();
    expect(peripheral.state, BleState.broadcasting);

    availability.add(AvailabilityState.poweredOff);
    await pumpEventQueue();
    expect(peripheral.state, BleState.idle);

    platform.advertising = PeripheralAdvertisingState.idle;
    platform.calls.clear();

    availability.add(AvailabilityState.poweredOn);
    await pumpEventQueue();

    expect(
      platform.calls,
      containsAll(<String>['addService', 'startAdvertising']),
    );
    expect(peripheral.state, BleState.broadcasting);
  });

  test('an advertising-idle event landing before the adapter event still '
      'resumes', () async {
    // The patched plugin pushes `advertising → idle` and the availability
    // change from the same adapter broadcast, so by the time `poweredOff`
    // arrives the cached state is already idle. Resume must follow intent.
    final availability = StreamController<AvailabilityState>();
    addTearDown(availability.close);
    final peripheral = buildPeripheral(events: availability.stream);

    await peripheral.startAdvertising();

    platform.updateAdvertisingState(
      BlePeripheralAdvertisingStateChanged(
        PeripheralAdvertisingState.idle,
        null,
      ),
    );
    await pumpEventQueue();
    expect(peripheral.state, BleState.idle);

    availability.add(AvailabilityState.poweredOff);
    await pumpEventQueue();

    platform.calls.clear();
    availability.add(AvailabilityState.poweredOn);
    await pumpEventQueue();

    expect(
      platform.calls,
      containsAll(<String>['addService', 'startAdvertising']),
    );
    expect(peripheral.state, BleState.broadcasting);
  });

  test('an explicit stop does not resume after Bluetooth comes back', () async {
    final availability = StreamController<AvailabilityState>();
    addTearDown(availability.close);
    final peripheral = buildPeripheral(events: availability.stream);

    await peripheral.startAdvertising();
    await peripheral.stopAdvertising();
    expect(peripheral.state, BleState.idle);

    availability.add(AvailabilityState.poweredOff);
    await pumpEventQueue();
    platform.calls.clear();
    availability.add(AvailabilityState.poweredOn);
    await pumpEventQueue();

    expect(platform.calls, isEmpty);
    expect(peripheral.state, BleState.idle);
  });

  test('starting with Bluetooth off asks the system to enable it', () async {
    platform.readiness = PeripheralReadinessState.bluetoothOff;
    var prompts = 0;
    final peripheral = BlePeripheralUniversal(
      permissions: _GrantedBlePermissions(),
      availabilityStream: const Stream<AvailabilityState>.empty(),
      requestBluetoothEnable: () async {
        prompts++;
        platform.readiness = PeripheralReadinessState.ready;
        return true;
      },
    );
    addTearDown(peripheral.dispose);

    await peripheral.startAdvertising();

    expect(prompts, 1);
    expect(peripheral.state, BleState.broadcasting);
    expect(platform.calls, contains('addService'));
  });

  test('declining the enable request reports an error', () async {
    platform.readiness = PeripheralReadinessState.bluetoothOff;
    final peripheral = BlePeripheralUniversal(
      permissions: _GrantedBlePermissions(),
      availabilityStream: const Stream<AvailabilityState>.empty(),
      requestBluetoothEnable: () async => false,
    );
    addTearDown(peripheral.dispose);

    await peripheral.startAdvertising();

    expect(peripheral.state, BleState.error);
    expect(platform.calls, isEmpty);
  });

  test('the automatic resume does not race a start that is already asking the '
      'system to enable Bluetooth', () async {
    final availability = StreamController<AvailabilityState>();
    addTearDown(availability.close);
    final enable = Completer<bool>();
    final peripheral = BlePeripheralUniversal(
      permissions: _GrantedBlePermissions(),
      availabilityStream: availability.stream,
      requestBluetoothEnable: () => enable.future,
    );
    addTearDown(peripheral.dispose);

    await peripheral.startAdvertising();

    // Bluetooth goes off: advertising idle + availability, as on device.
    platform.advertising = PeripheralAdvertisingState.idle;
    availability.add(AvailabilityState.poweredOff);
    await pumpEventQueue();
    expect(peripheral.state, BleState.idle);

    platform.readiness = PeripheralReadinessState.bluetoothOff;
    platform.calls.clear();

    // The user taps another chain while Bluetooth is off: this start blocks on
    // the system prompt.
    final tapStart = peripheral.startAdvertising();
    await pumpEventQueue();
    expect(platform.calls, isEmpty);

    // The adapter comes up while the prompt is open — must not start twice.
    availability.add(AvailabilityState.poweredOn);
    await pumpEventQueue();

    enable.complete(true);
    platform.readiness = PeripheralReadinessState.ready;
    await tapStart;

    expect(
      platform.calls.where((c) => c == 'addService').length,
      1,
      reason: 'exactly one rebuild should run',
    );
    expect(peripheral.state, BleState.broadcasting);
  });

  test('a prompt that times out after the user answered late still recovers',
      () async {
    final availability = StreamController<AvailabilityState>();
    addTearDown(availability.close);
    final gate = Completer<bool>();
    final peripheral = BlePeripheralUniversal(
      permissions: _GrantedBlePermissions(),
      availabilityStream: availability.stream,
      requestBluetoothEnable: () => gate.future,
    );
    addTearDown(peripheral.dispose);

    await peripheral.startAdvertising();

    platform.advertising = PeripheralAdvertisingState.idle;
    availability.add(AvailabilityState.poweredOff);
    await pumpEventQueue();

    platform.readiness = PeripheralReadinessState.bluetoothOff;
    platform.calls.clear();

    final tapStart = peripheral.startAdvertising();
    await pumpEventQueue();

    // The adapter comes up while the prompt is still open.
    platform.readiness = PeripheralReadinessState.ready;
    availability.add(AvailabilityState.poweredOn);
    await pumpEventQueue();

    // The user answers after the command's timeout elapsed.
    gate.completeError(TimeoutException('Bluetooth enable prompt'));
    await tapStart;
    await pumpEventQueue();
    await pumpEventQueue();

    expect(peripheral.state, BleState.broadcasting);
    expect(platform.calls, contains('addService'));
  });
}
