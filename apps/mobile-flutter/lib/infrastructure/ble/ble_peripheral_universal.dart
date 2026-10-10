/// BLE GATT server peripheral — Ledger Nano X-compatible, on `universal_ble`.
///
/// Replaces the `ble_gatt_server` 0.1.0 implementation, whose `AdvertiseData`
/// payload never reached the air: advertising reported success and the GATT
/// service registered (`onServiceAdded status=0`), yet an off-air scan saw only
/// the local name — no service UUID, service data, manufacturer data, TX power
/// or advertising flags. Only the name got through, and that travels via
/// `BluetoothAdapter.name`, bypassing the payload entirely. Central-side causes
/// were ruled out first: Chrome unions advertisement and scan-response UUIDs
/// (`STLSetUnion` in `device/bluetooth/bluetooth_device.cc`), and dropping the
/// scan response did not bring the UUID back.
///
/// This implementation also gains signals the old plugin never exposed:
/// service-registration results, real advertising state, and MTU changes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import '../../core/interfaces/ble_peripheral.dart';
import '../../core/models/ble_types.dart';

class BlePeripheralUniversal implements IBlePeripheral {
  BlePeripheralUniversal();

  // ── Ledger BLE framing ───────────────────────────────────────────────

  static const int _tagApdu = 0x05;
  static const int _tagGetMtu = 0x08;

  static const int _defaultMtu = 20;

  // ── State ────────────────────────────────────────────────────────────

  BleState _state = BleState.idle;
  String _deviceName = 'OpenLedgerAppApp';
  int _mtu = _defaultMtu;
  bool _disposed = false;

  String? _connectedDeviceId;

  /// Buffered first response fragment, served on a GATT read.
  ///
  /// OKX Wallet reads the response characteristic instead of subscribing to
  /// notifications, so the latest response must stay retrievable.
  Uint8List? _bufferedResponse;

  final Map<int, Uint8List> _incomingChunks = {};
  int _incomingTotalLen = 0;

  final _apduController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<BleState>.broadcast();
  final _logController = StreamController<String>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // ── Public surface (kept identical to the previous implementation) ────

  @override
  BleState get state => _state;
  @override
  Stream<Uint8List> get apduStream => _apduController.stream;
  @override
  Stream<BleState> get stateStream => _stateController.stream;
  @override
  Stream<String> get logStream => _logController.stream;
  @override
  String get deviceName => _deviceName;
  @override
  int get mtu => _mtu;

  // ── Lifecycle ────────────────────────────────────────────────────────

  /// Poll peripheral readiness until it leaves `unknown`, or the budget runs
  /// out.
  ///
  /// iOS: the first peripheral API call lazily constructs `CBPeripheralManager`,
  /// whose state starts at `.unknown` and only resolves asynchronously (to
  /// `.poweredOn` after the Bluetooth permission prompt is answered, or to
  /// `.unauthorized`/`.poweredOff` on failure). A one-shot read — which is what
  /// Android's synchronous adapter check tolerates — would almost always see
  /// `unknown` on iOS and misreport it as fatal. Terminal states
  /// (ready/bluetoothOff/unauthorized/unsupported) return immediately.
  Future<PeripheralReadinessState> _awaitReadiness() async {
    const pollInterval = Duration(milliseconds: 250);
    const budget = Duration(seconds: 20); // covers a slow permission prompt
    var waited = Duration.zero;

    var readiness = await UniversalBlePeripheral.getAvailabilityState();
    while (readiness == PeripheralReadinessState.unknown && waited < budget) {
      await Future<void>.delayed(pollInterval);
      waited += pollInterval;
      readiness = await UniversalBlePeripheral.getAvailabilityState();
    }
    return readiness;
  }

  @override
  Future<void> startAdvertising() async {
    _ensureNotDisposed();

    if (_state == BleState.broadcasting || _state == BleState.connected) {
      _log('Already advertising or connected.');
      return;
    }

    try {
      final readiness = await _awaitReadiness();
      if (readiness != PeripheralReadinessState.ready) {
        _log('⚠ Peripheral not ready: ${readiness.name}');
        _transition(BleState.error);
        return;
      }

      // Clear anything a previous run left registered; the old plugin's
      // equivalent leak surfaced as ADVERTISE_FAILED_ALREADY_STARTED, which
      // kept a stale payload on the air.
      await UniversalBlePeripheral.stopAdvertising();
      await UniversalBlePeripheral.clearServices();

      _attachHandlers();

      await UniversalBlePeripheral.addService(_buildService());

      final registered = await UniversalBlePeripheral.getServices();
      final present = registered
          .any((s) => s.toLowerCase() == bleServiceUuid.toLowerCase());
      _log('GATT services registered: $registered (target present: $present)');
      if (!present) {
        _log('⚠ Service $bleServiceUuid missing after addService.');
        _transition(BleState.error);
        return;
      }

      // Primary packet carries flags(3) + name(11) = 14B; the 128-bit UUID(18B)
      // moves to the scan response via addServicesInScanResponse. Both fit their
      // 31-byte legacy budgets. Chrome unions advertised + scan-response UUIDs
      // (see AGENTS.md #17), so services-filter matching still works.
      await UniversalBlePeripheral.startAdvertising(
        services: [bleServiceUuid],
        localName: _deviceName,
        platformConfig: PeripheralPlatformConfig(
          android: PeripheralAndroidOptions(
            addServicesInScanResponse: true,
          ),
        ),
      );

      // The advertising-state stream drives the transition, but poll once in
      // case the stream event landed before the listener attached.
      final advState = await UniversalBlePeripheral.getAdvertisingState();
      _log('Advertising state: ${advState.name}');
      if (advState == PeripheralAdvertisingState.advertising) {
        _transition(BleState.broadcasting);
      }
    } catch (e) {
      _log('⚠ BLE startAdvertising error: $e');
      _transition(BleState.error);
    }
  }

  @override
  Future<void> stopAdvertising() async {
    _ensureNotDisposed();

    try {
      await UniversalBlePeripheral.stopAdvertising();
      await UniversalBlePeripheral.clearServices();
    } catch (e) {
      _log('⚠ BLE stop error: $e');
    }

    _connectedDeviceId = null;
    _bufferedResponse = null;
    _incomingChunks.clear();
    _incomingTotalLen = 0;
    _mtu = _defaultMtu;

    _transition(BleState.idle);
    _log('BLE advertising stopped.');
  }

  @override
  Future<void> setDeviceName(String name) async {
    _ensureNotDisposed();

    if (name.isEmpty) {
      _log('⚠ Device name cannot be empty.');
      return;
    }

    if (name.length > maxBleDeviceNameLength) {
      _log('⚠ Device name "$name" is ${name.length} chars; '
          'max is $maxBleDeviceNameLength. Ignored.');
      return;
    }

    _deviceName = name;
    _log('Device name set to "$_deviceName".');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    UniversalBlePeripheral.setWriteRequestHandlers(null);
    UniversalBlePeripheral.setReadRequestHandlers(null);

    _apduController.close();
    _stateController.close();
    _logController.close();
  }

  // ── Outgoing APDU ────────────────────────────────────────────────────

  @override
  Future<void> sendApduResponse(Uint8List response) async {
    _ensureNotDisposed();

    final deviceId = _connectedDeviceId;
    if (deviceId == null) {
      _log('⚠ Cannot send response: no device connected.');
      return;
    }

    _log('APDU response: ${_bytesToHex(response)}');

    final fragments = _fragmentOutgoingApdu(response);
    if (fragments.isNotEmpty) {
      _bufferedResponse = fragments.first;
    }

    for (final fragment in fragments) {
      try {
        await UniversalBlePeripheral.updateCharacteristicValue(
          characteristicId: bleApduResponseCharacteristicUuid,
          value: fragment,
          deviceId: deviceId,
        );
      } catch (e) {
        _log('⚠ Notify failed: $e');
        return;
      }
    }
  }

  // ── Service definition ───────────────────────────────────────────────

  BlePeripheralService _buildService() => BlePeripheralService(
        uuid: bleServiceUuid,
        characteristics: [
          BlePeripheralCharacteristic(
            uuid: bleApduResponseCharacteristicUuid,
            properties: [
              CharacteristicProperty.read,
              CharacteristicProperty.notify,
            ],
            permissions: [PeripheralAttributePermission.readable],
            // Android: the stack does not auto-create the CCCD — declare it.
            // iOS/macOS: CoreBluetooth auto-creates the CCCD for .notify
            // characteristics and throws NSInternalInconsistencyException
            // (SIGABRT) if a manual 0x2902 descriptor is published — see
            // crash log Runner-2026-09-08-194434.ips
            // (-[CBMutableDescriptor initWithType:value:]).
            descriptors: Platform.isIOS || Platform.isMacOS
                ? const []
                : [BlePeripheralDescriptor(uuid: bleCccdDescriptorUuid)],
          ),
          BlePeripheralCharacteristic(
            uuid: bleApduCommandCharacteristicUuid,
            properties: [CharacteristicProperty.write],
            permissions: [PeripheralAttributePermission.writeable],
          ),
          BlePeripheralCharacteristic(
            uuid: bleApduWriteCommandCharacteristicUuid,
            properties: [CharacteristicProperty.writeWithoutResponse],
            permissions: [PeripheralAttributePermission.writeable],
          ),
        ],
      );

  // ── Event wiring ─────────────────────────────────────────────────────

  void _attachHandlers() {
    if (_subscriptions.isNotEmpty) return;

    _subscriptions.add(
      UniversalBlePeripheral.advertisingStateStream.listen((e) {
        _log('Advertising → ${e.state.name}${e.error != null ? " (${e.error})" : ""}');
        switch (e.state) {
          case PeripheralAdvertisingState.advertising:
            if (_state != BleState.connected) _transition(BleState.broadcasting);
          case PeripheralAdvertisingState.error:
            _transition(BleState.error);
          case PeripheralAdvertisingState.idle:
            if (_state != BleState.connected) _transition(BleState.idle);
          case PeripheralAdvertisingState.starting:
          case PeripheralAdvertisingState.stopping:
            break;
        }
      }),
    );

    _subscriptions.add(
      UniversalBlePeripheral.serviceAddedStream.listen((e) {
        if (e.error != null) {
          _log('⚠ Service ${e.serviceId} failed to register: ${e.error}');
        } else {
          _log('Service registered: ${e.serviceId}');
        }
      }),
    );

    _subscriptions.add(
      UniversalBlePeripheral.connectionStateStream.listen((e) {
        _log('Device ${e.deviceId} ${e.connected ? "connected" : "disconnected"}');
        if (e.connected) {
          _connectedDeviceId = e.deviceId;
          _transition(BleState.connected);
        } else if (e.deviceId == _connectedDeviceId) {
          _connectedDeviceId = null;
          _bufferedResponse = null;
          _incomingChunks.clear();
          _incomingTotalLen = 0;
          _transition(BleState.broadcasting);
        }
      }),
    );

    _subscriptions.add(
      UniversalBlePeripheral.mtuChangedStream.listen((e) {
        _mtu = e.mtu;
        _log('MTU changed: ${e.mtu}');
      }),
    );

    _subscriptions.add(
      UniversalBlePeripheral.characteristicSubscriptionStream.listen((e) {
        _log('${e.deviceId} ${e.isSubscribed ? "subscribed to" : "unsubscribed from"} '
            '${e.characteristicId}');
      }),
    );

    UniversalBlePeripheral.setWriteRequestHandlers(_onWriteRequest);
    UniversalBlePeripheral.setReadRequestHandlers(_onReadRequest);
  }

  PeripheralWriteRequestResult? _onWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    _connectedDeviceId ??= deviceId;

    if (value == null || value.isEmpty) {
      return PeripheralWriteRequestResult(status: 0);
    }

    _log('GATT write: ${_bytesToHex(value)}');

    final tag = value[0];
    if (tag == _tagGetMtu) {
      _log('GET_MTU received, MTU=$_mtu');
      final reply = Uint8List.fromList([
        _tagGetMtu,
        0x00,
        0x00,
        0x00,
        0x02,
        (_mtu >> 8) & 0xFF,
        _mtu & 0xFF,
      ]);
      UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: bleApduResponseCharacteristicUuid,
        value: reply,
        deviceId: deviceId,
      ).catchError((Object e) => _log('⚠ MTU reply failed: $e'));
    } else if (tag == _tagApdu) {
      _processIncomingApduFragment(value);
    } else {
      _log('⚠ Unknown tag: 0x${tag.toRadixString(16)}');
    }

    return PeripheralWriteRequestResult(status: 0);
  }

  PeripheralReadRequestResult? _onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    final buffered = _bufferedResponse;
    if (buffered == null) {
      return PeripheralReadRequestResult(value: Uint8List(0));
    }

    _log('GATT read served ${buffered.length} bytes');
    final slice = offset < buffered.length
        ? Uint8List.sublistView(buffered, offset)
        : Uint8List(0);
    return PeripheralReadRequestResult(value: slice);
  }

  // ── APDU reassembly (incoming) ───────────────────────────────────────

  /// Ledger BLE framing, tag-first with no channel prefix:
  /// - first chunk `[0x05, seq_hi, seq_lo, total_len_hi, total_len_lo, ...]`
  /// - continuation `[0x05, seq_hi, seq_lo, ...]`
  void _processIncomingApduFragment(Uint8List chunk) {
    if (chunk.length < 3) {
      _log('⚠ APDU fragment too short: ${chunk.length} bytes');
      return;
    }

    final seqIndex = (chunk[1] << 8) | chunk[2];

    int headerSize;
    int totalLen;

    if (seqIndex == 0 && chunk.length >= 5) {
      totalLen = (chunk[3] << 8) | chunk[4];
      headerSize = 5;
      _incomingTotalLen = totalLen;
      _incomingChunks.clear();
      _log('APDU incoming: total_len=$totalLen, seq=$seqIndex, '
          'payload=${chunk.length - headerSize} bytes');
    } else {
      totalLen = _incomingTotalLen;
      headerSize = 3;
      _log('APDU incoming: seq=$seqIndex, '
          'payload=${chunk.length - headerSize} bytes');
    }

    if (totalLen <= 0) {
      _log('⚠ APDU fragment: invalid total_len=$totalLen');
      return;
    }

    _incomingChunks[seqIndex] = Uint8List.sublistView(chunk, headerSize);

    var accumulatedLen = 0;
    for (final entry in _incomingChunks.entries) {
      accumulatedLen += entry.value.length;
    }

    if (accumulatedLen >= totalLen) {
      _emitCompleteApdu(totalLen);
    }
  }

  void _emitCompleteApdu(int totalLen) {
    final sortedKeys = _incomingChunks.keys.toList()..sort();
    final buffer = Uint8List(totalLen);
    var offset = 0;

    for (final key in sortedKeys) {
      final chunk = _incomingChunks[key]!;
      final copyLen =
          (offset + chunk.length <= totalLen) ? chunk.length : totalLen - offset;
      buffer.setRange(offset, offset + copyLen, chunk);
      offset += copyLen;
      if (offset >= totalLen) break;
    }

    _incomingChunks.clear();
    _incomingTotalLen = 0;

    _log('APDU command received: ${_bytesToHex(buffer)}');

    if (!_apduController.isClosed) {
      _apduController.add(buffer);
    }
  }

  // ── APDU fragmentation (outgoing) ────────────────────────────────────

  List<Uint8List> _fragmentOutgoingApdu(Uint8List apdu) {
    final mtu = _mtu > 0 ? _mtu : _defaultMtu;
    final totalLen = apdu.length;
    final fragments = <Uint8List>[];

    var offset = 0;
    var seqIndex = 0;

    while (offset < totalLen) {
      final isFirst = seqIndex == 0;
      final headerSize = isFirst ? 5 : 3;
      final maxPayload = mtu - headerSize;
      final remaining = totalLen - offset;
      final payloadSize = remaining < maxPayload ? remaining : maxPayload;

      final fragment = Uint8List(headerSize + payloadSize);
      fragment[0] = _tagApdu;
      fragment[1] = (seqIndex >> 8) & 0xFF;
      fragment[2] = seqIndex & 0xFF;

      if (isFirst) {
        fragment[3] = (totalLen >> 8) & 0xFF;
        fragment[4] = totalLen & 0xFF;
      }

      fragment.setRange(headerSize, headerSize + payloadSize, apdu, offset);

      fragments.add(fragment);
      offset += payloadSize;
      seqIndex++;
    }

    return fragments;
  }

  // ── Private helpers ──────────────────────────────────────────────────

  void _transition(BleState next) {
    if (_state == next) return;
    _state = next;
    _log('BLE state → ${next.name}');
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _log(String message) {
    if (!_logController.isClosed) {
      _logController.add(message);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BlePeripheralUniversal has been disposed.');
    }
  }

  static String _bytesToHex(Uint8List bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

/// App-facing name for the BLE peripheral.

typedef BlePeripheral = BlePeripheralUniversal;
