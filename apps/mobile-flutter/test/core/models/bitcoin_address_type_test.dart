/// Bitcoin's four address types are encoded in the derivation path, so the
/// parser is the only thing standing between "show the address" and "show an
/// unspendable one". These tests pin the mapping.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger_app/core/models/bitcoin_address_type.dart';

void main() {
  test('each purpose maps to its address type', () {
    expect(
      BitcoinAddressType.fromPath("m/44'/0'/0'/0/0"),
      BitcoinAddressType.legacy,
    );
    expect(
      BitcoinAddressType.fromPath("m/49'/0'/0'/0/0"),
      BitcoinAddressType.nestedSegwit,
    );
    expect(
      BitcoinAddressType.fromPath("m/84'/0'/0'/0/0"),
      BitcoinAddressType.nativeSegwit,
    );
    expect(
      BitcoinAddressType.fromPath("m/86'/0'/0'/0/0"),
      BitcoinAddressType.taproot,
    );
  });

  test('native segwit keeps profile index 0 so old accounts stay put', () {
    expect(BitcoinAddressType.nativeSegwit.profileIndex, 0);
    expect(BitcoinAddressType.legacy.profileIndex, 1);
    expect(BitcoinAddressType.nestedSegwit.profileIndex, 2);
    expect(BitcoinAddressType.taproot.profileIndex, 3);
  });

  test('pathForIndex round-trips through fromPath', () {
    for (final type in BitcoinAddressType.values) {
      for (final index in [0, 1, 7]) {
        final path = type.pathForIndex(index);
        expect(BitcoinAddressType.fromPath(path), type, reason: path);
        expect(path, startsWith("m/${type.purpose}'/0'/0'/0/"));
      }
    }
  });

  test('non-Bitcoin or non-template paths are rejected', () {
    // ETH's coin type is not Bitcoin even though the purpose matches.
    expect(BitcoinAddressType.fromPath("m/44'/60'/0'/0/0"), isNull);
    // Unsupported purpose.
    expect(BitcoinAddressType.fromPath("m/1'/0'/0'/0/0"), isNull);
    // Wrong template: change index or depth differs from the account layout.
    expect(BitcoinAddressType.fromPath("m/84'/0'/0'/1/0"), isNull);
    expect(BitcoinAddressType.fromPath("m/84'/0'/0'/0"), isNull);
    // Hardened address index is not how these accounts are derived.
    expect(BitcoinAddressType.fromPath("m/84'/0'/0'/0/0'"), isNull);
    expect(BitcoinAddressType.fromPath(''), isNull);
  });

  test('persisted ids match the Rust identifiers', () {
    for (final type in BitcoinAddressType.values) {
      expect(BitcoinAddressType.fromId(type.id), type);
    }
    expect(BitcoinAddressType.fromId('p2tr'), BitcoinAddressType.taproot);
    expect(BitcoinAddressType.fromId('unknown'), isNull);
    expect(BitcoinAddressType.fromId(null), isNull);
  });
}
