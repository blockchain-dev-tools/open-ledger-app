import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/ble_permissions.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';
import 'package:open_ledger_app/infrastructure/ble/ble_peripheral_universal.dart';

/// Denies every runtime permission the peripheral asks for.
class _DeniedBlePermissions implements IBlePermissions {
  @override
  Future<bool> ensureGranted() async => false;
}

void main() {
  // `dispose()` tears down `universal_ble`'s write/read request handlers,
  // which reach `ServicesBinding.instance`; the binding must exist first.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'starting advertising with denied BLE permissions reports an error '
    'instead of throwing',
    () async {
      final peripheral =
          BlePeripheralUniversal(permissions: _DeniedBlePermissions());
      addTearDown(peripheral.dispose);

      final logs = <String>[];
      final sub = peripheral.logStream.listen(logs.add);
      addTearDown(sub.cancel);

      await peripheral.startAdvertising();
      await pumpEventQueue();

      expect(peripheral.state, BleState.error);
      expect(
        logs.any((line) => line.contains('permission denied')),
        isTrue,
        reason: 'the denial must be surfaced in the activity log',
      );
    },
  );
}
