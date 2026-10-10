/// Well-known BIP-39 test vector (12 words — public test data, not a secret).
const String sampleMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

/// Creation data payload for [VerifyMnemonicScreen].
const Map<String, String> sampleCreationData = {
  'mnemonic': sampleMnemonic,
  'passphrase': '',
};
