/// Sample 24-word Enigma mnemonic for the design gallery.
///
/// Deterministic placeholder words — the real Enigma flow derives these
/// from the user's riddle + secret via the Rust SDK.
const List<String> sampleEnigmaWords = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
  'account', 'accuse', 'achieve', 'acid', 'acoustic', 'acquire',
  'across', 'act', 'action', 'actor', 'actress', 'actual',
];

/// Dummy entropy hex matching [sampleEnigmaWords] for preview purposes.
const String sampleEnigmaEntropyHex =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
