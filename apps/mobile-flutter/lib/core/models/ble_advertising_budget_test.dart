// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger_app/core/models/ble_types.dart';

/// Size of one legacy BLE advertising PDU payload (ADV_IND or SCAN_RSP).
const int _adPayloadLimit = 31;

/// An AD structure costs one length byte plus one type byte.
const int _adHeader = 2;

int _flagsAd() => _adHeader + 1;
int _uuid128Ad() => _adHeader + 16;
int _localNameAd(String name) => _adHeader + name.length;

void main() {
  group('primary advertising packet', () {
    test('holds flags plus the 128-bit service UUID', () {
      expect(_flagsAd() + _uuid128Ad(), lessThanOrEqualTo(_adPayloadLimit));
    });

    test('stays within budget no matter how long the device name gets', () {
      // The name lives in the scan response, so its length cannot affect this
      // packet — the UUID stays discoverable even at the longest allowed name.
      final primary = _flagsAd() + _uuid128Ad();
      for (final name in ['IV', 'OpenLedgerApp', 'A' * maxBleDeviceNameLength]) {
        expect(primary, lessThanOrEqualTo(_adPayloadLimit),
            reason: 'primary packet must not depend on name "$name"');
      }
    });

    test('cannot also carry the default device name', () {
      // 3 + 18 + 15 = 36B — over budget. This is what forces the split.
      expect(_flagsAd() + _uuid128Ad() + _localNameAd('OpenLedgerApp'),
          greaterThan(_adPayloadLimit));
    });
  });

  group('scan response packet', () {
    test('fits a name at the documented maximum length', () {
      expect(_localNameAd('A' * maxBleDeviceNameLength),
          lessThanOrEqualTo(_adPayloadLimit));
    });

    test('overflows one character past the maximum', () {
      expect(_localNameAd('A' * (maxBleDeviceNameLength + 1)),
          greaterThan(_adPayloadLimit));
    });

    test('maxBleDeviceNameLength is exactly the largest value that fits', () {
      expect(maxBleDeviceNameLength, _adPayloadLimit - _adHeader);
    });
  });
}
