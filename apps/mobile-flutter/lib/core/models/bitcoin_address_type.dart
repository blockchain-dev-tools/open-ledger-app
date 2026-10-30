/// Bitcoin's four single-key address types.
///
/// They are **not** four encodings of one key: each type lives on its own
/// BIP-43 purpose path, so the same seed yields four unrelated accounts.
/// A `m/84'` key formatted as a `1…` address is unspendable, therefore the
/// type is always derived from the path — never chosen independently.
///
/// | type | purpose | prefix |
/// |---|---|---|
/// | legacy (P2PKH) | `m/44'/0'/…` | `1…` |
/// | nested segwit (P2SH-P2WPKH) | `m/49'/0'/…` | `3…` |
/// | native segwit (P2WPKH) | `m/84'/0'/…` | `bc1q…` |
/// | taproot (P2TR) | `m/86'/0'/…` | `bc1p…` |
///
/// [profileIndex] must match `ACCOUNT_PROFILES` in
/// `crates/chain-app-bitcoin/src/lib.rs` — index 0 is native segwit so the
/// accounts created before taproot support keep their addresses.
library;

enum BitcoinAddressType {
  nativeSegwit(purpose: 84, profileIndex: 0),
  legacy(purpose: 44, profileIndex: 1),
  nestedSegwit(purpose: 49, profileIndex: 2),
  taproot(purpose: 86, profileIndex: 3);

  const BitcoinAddressType({
    required this.purpose,
    required this.profileIndex,
  });

  /// BIP-43 purpose segment.
  final int purpose;

  /// `account_profile_index` sent to the Rust chain app.
  final int profileIndex;

  /// The account path for [index] under this type.
  String pathForIndex(int index) => "m/$purpose'/0'/0'/0/$index";

  /// Parse a Bitcoin path, or `null` when [path] is not one of the four
  /// `m/{44,49,84,86}'/0'/0'/0/{index}` templates.
  static BitcoinAddressType? fromPath(String path) {
    final parts = path.split('/');
    if (parts.length != 6 || parts[0] != 'm') return null;
    if (parts[2] != "0'" || parts[3] != "0'" || parts[4] != '0') return null;
    // The address index must be a plain (non-hardened) number, otherwise the
    // path is not one the chain app can derive.
    if (int.tryParse(parts[5]) == null) return null;
    final purpose = _hardened(parts[1]);
    if (purpose == null) return null;
    for (final type in values) {
      if (type.purpose == purpose) return type;
    }
    return null;
  }

  /// Parse a persisted `address_type` string (Rust side identifiers).
  static BitcoinAddressType? fromId(String? id) {
    for (final type in values) {
      if (type.id == id) return type;
    }
    return null;
  }

  /// Stable identifier matching the Rust module's `as_str()`.
  String get id => switch (this) {
        BitcoinAddressType.legacy => 'p2pkh',
        BitcoinAddressType.nestedSegwit => 'p2sh-p2wpkh',
        BitcoinAddressType.nativeSegwit => 'p2wpkh',
        BitcoinAddressType.taproot => 'p2tr',
      };
}

/// Reads a hardened BIP-32 segment like `84'`, returning `null` when it is not
/// hardened or not numeric.
int? _hardened(String segment) {
  if (!segment.endsWith("'")) return null;
  return int.tryParse(segment.substring(0, segment.length - 1));
}
