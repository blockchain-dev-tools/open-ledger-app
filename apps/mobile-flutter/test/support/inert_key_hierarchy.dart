/// Inert implementations of the key-hierarchy part of `ICryptoService`.
///
/// Fakes that never exercise tier verifiers / raw-key AEAD / the versioned PIN
/// KDF can mix this in to satisfy the interface without writing stub methods.
/// Fakes that *do* exercise the key hierarchy (e.g. the PIN matching tests)
/// must override these instead of mixing this in.
mixin InertKeyHierarchy {
  String? deriveMasterKey(String pin, String saltHex, int version) => null;

  String? hkdfExpand32(String prkHex, String info) => null;

  String? aeadEncryptWithKey(String plaintext, String keyHex) => null;

  String? aeadDecryptWithKey(String ciphertextHex, String keyHex) => null;
}
