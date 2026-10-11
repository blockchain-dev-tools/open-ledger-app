import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../../core/interfaces/ble_permissions.dart';

/// Requests the Android BLE runtime permissions through `permission_handler`.
///
/// The three "Nearby devices" permissions are declared in the manifest but are
/// denied by default on a fresh install, so the app must ask before
/// advertising; otherwise the GATT server throws `SecurityException`.
///
/// Android ≤11 deliberately requests nothing: those three are not runtime
/// permissions there, the install-time `BLUETOOTH` / `BLUETOOTH_ADMIN` already
/// cover peripheral advertising, and location only gates *scanning*, which this
/// app never does.
class BlePermissions implements IBlePermissions {
  const BlePermissions();

  static const List<Permission> _androidPermissions = <Permission>[
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ];

  @override
  Future<bool> ensureGranted() async {
    if (!Platform.isAndroid) return true;

    final statuses = await _androidPermissions.request();
    return statuses.values.every((status) => status.isGranted);
  }
}
