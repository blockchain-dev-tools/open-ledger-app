/// Inert implementations of the **export** part of `ICryptoService`.
///
/// Companion to `InertKeyHierarchy`: fakes that never derive a real public key
/// or encode a private key can mix this in to satisfy the interface without
/// writing two `null` stubs each. Fakes that *do* exercise export (e.g.
/// `account_service_test`) must override these instead of mixing this in.
library;

import 'dart:typed_data';

mixin InertExport {
  Uint8List? publicKeyForChain(String chain, String privkeyHex) => null;

  String? encodePrivateKey(String chain, String privkeyHex) => null;
}
