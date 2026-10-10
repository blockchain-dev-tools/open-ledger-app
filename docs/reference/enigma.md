# Enigma deterministic mnemonic derivation

Enigma derives an English 24-word BIP-39 mnemonic from a phrase, a secret and the selected input-wordlist language. The Rust [implementation](../../crates/open-ledger-biz/src/enigma.rs) and [test vectors](../../crates/open-ledger-biz/src/enigma_test.rs) are authoritative. Preserve exact output bytes across refactors: changing this algorithm changes the recoverable wallet.

## Algorithm

1. Tokenize the phrase according to the selected BIP-39 language: Simplified/Traditional Chinese and Japanese use non-whitespace characters; other languages use lowercased whitespace-separated words.
2. Look up each token in that language's BIP-39 wordlist. Unrecognized tokens contribute no index.
3. Take at most the first 16 matched indices. Encode each as unsigned 16-bit big-endian and concatenate the bytes. The current implementation uses a variable-length byte sequence with no padding.
4. Compute `phraseHash = keccak256(indexBytes)`.
5. For a nonempty secret, compute `entropy = keccak256(phraseHash || keccak256(secret UTF-8))`. For an empty secret, compute `entropy = keccak256(phraseHash)`.
6. Encode the resulting 32 bytes as a 24-word **English** BIP-39 mnemonic. Displaying that entropy in another language does not change the English mnemonic used for wallet seed derivation.

Input language, matched token order, secret text and byte encoding all matter. This is not interchangeable with other phrase-to-mnemonic tools merely because they use BIP-39 or keccak256.

## Security and recovery

Hashing does not create entropy absent from the chosen phrase/secret. Predictable human inputs remain susceptible to guessing; deterministic derivation is not equivalent to random mnemonic generation. Preserve the complete original recovery inputs including language and any BIP-39 passphrase separately from the displayed mnemonic.

[Enigma screen](../../apps/mobile-flutter/lib/ui/screens/enigma/enigma_screen.dart), [mnemonic service](../../apps/mobile-flutter/lib/services/mnemonic_service.dart), [Rust language mapping](../../crates/open-ledger-biz/src/mnemonic.rs).
