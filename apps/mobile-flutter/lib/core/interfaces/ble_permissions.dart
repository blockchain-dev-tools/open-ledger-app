/// Runtime permissions the BLE peripheral needs before it can advertise.
///
/// Android 12+ (API 31) moved advertising / connecting / scanning into a
/// runtime "Nearby devices" permission group; the manifest declares them, but
/// a fresh install leaves them denied until the app asks. Without a request the
/// GATT server throws `SecurityException` the moment advertising starts.
///
/// Kept as a `core/` contract so `BlePeripheralUniversal` can be unit-tested
/// with a fake gate that never touches a platform channel.
abstract class IBlePermissions {
  /// Requests every permission the peripheral needs and reports whether they
  /// are all granted.
  ///
  /// Returns `true` immediately on platforms that do not gate BLE behind a
  /// runtime permission (iOS surfaces denial through CoreBluetooth readiness;
  /// desktop / web have no such gate).
  Future<bool> ensureGranted();
}
