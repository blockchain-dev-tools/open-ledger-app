import 'dart:convert';

/// Multi-round FNV-1a hash, returning the first 8 hex characters.
///
/// Used for generating lightweight mnemonic fingerprints where
/// cryptographic strength is not required.
String fnv1aFingerprint(String input) {
  final bytes = utf8.encode(input);
  int h = 0x811c9dc5;
  for (int round = 0; round < 5000; round++) {
    for (final b in bytes) {
      h ^= b;
      h *= 0x01000193;
      h &= 0xFFFFFFFF;
    }
  }
  return h.toRadixString(16).padLeft(8, '0');
}
