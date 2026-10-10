/// BLE (Bluetooth Low Energy) peripheral types and constants.
///
/// Ported from the original TypeScript implementation.
///
/// GATT service UUID is the same as Ledger Nano X so that existing
/// wallet clients (Metamask, Phantom, Ledger Live) can discover the device.
library;

/// BLE state machine — only one state is active at a time.
enum BleState {
  /// No connection, not advertising.
  idle,

  /// Advertising / broadcasting — visible to BLE centrals.
  broadcasting,

  /// Connected to a BLE central, ready for APDU exchange.
  connected,

  /// A recoverable or non-recoverable error occurred.
  error,
}

/// Ledger Nano X-compatible GATT service UUID.
///
/// This is the UUID that Ledger Live, Metamask, Phantom, and other
/// wallet clients scan for. Using the same UUID allows the device to
/// be discovered without client-side modifications.
const String bleServiceUuid = '13d63400-2c97-0004-0000-4c6564676572';

/// Characteristic UUID for **APDU response** (notify by wallet, read by client).
///
/// Format: `13d63400-2c97-0004-0001-4c6564676572`
/// (last segment set to `0001` for the response characteristic).
const String bleApduResponseCharacteristicUuid =
    '13d63400-2c97-0004-0001-4c6564676572';

/// Characteristic UUID for **APDU command** (write by client, with response).
///
/// Format: `13d63400-2c97-0004-0002-4c6564676572`
/// (last segment set to `0002` for the command characteristic).
const String bleApduCommandCharacteristicUuid =
    '13d63400-2c97-0004-0002-4c6564676572';

/// Characteristic UUID for **APDU write command** (write without response).
///
/// Ledger Nano X supports this as an optimization — clients can write
/// APDU data without waiting for a GATT-level acknowledgement.
///
/// Format: `13d63400-2c97-0004-0003-4c6564676572`
const String bleApduWriteCommandCharacteristicUuid =
    '13d63400-2c97-0004-0003-4c6564676572';

/// Longest advertisable BLE device name.
///
/// The name is carried in the scan response, whose legacy payload is 31 bytes
/// and needs 2 of them for the AD length/type header.
const int maxBleDeviceNameLength = 29;

/// Standard CCCD (Client Characteristic Configuration Descriptor) UUID.
///
/// Required on the notify characteristic so that BLE centrals (MetaMask,
/// OKX Wallet, Ledger Live) can subscribe to APDU response notifications.
const String bleCccdDescriptorUuid = '00002902-0000-1000-8000-00805f9b34fb';

/// Information about a discovered or connected BLE device.
class BleDeviceInfo {
  /// Human-readable device name (e.g. "OpenLedgerAppApp").
  final String name;

  /// Bluetooth MAC address or UUID. `null` for unconnected devices
  /// where the address has not been resolved.
  final String? address;

  /// Whether this device is currently connected.
  final bool isConnected;

  const BleDeviceInfo({
    required this.name,
    this.address,
    this.isConnected = false,
  });

  @override
  String toString() =>
      'BleDeviceInfo(name: $name, address: ${address ?? 'unknown'}, '
      'isConnected: $isConnected)';
}

/// Represents a BLE error with context about the state when it occurred.
class BleError {
  /// Human-readable error description.
  final String message;

  /// The BLE state that was active when the error was raised.
  final BleState stateAtError;

  const BleError({
    required this.message,
    required this.stateAtError,
  });

  @override
  String toString() =>
      'BleError(message: $message, stateAtError: $stateAtError)';
}
