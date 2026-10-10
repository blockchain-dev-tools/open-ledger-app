import 'dart:typed_data';

import '../airgap/airgap_protocol.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EIP-4527 UR (Uniform Resource) Encoding Protocol
//
// Implements the Blockchain Commons Uniform Resource (UR) specification
// for encoding crypto wallet data as CBOR-tagged, base58-encoded UR strings.
//
// Supported types:
//   - CryptoHDKey (tag 303), CryptoKeypath (tag 304)
//   - CryptoCoinInfo (tag 305), CryptoAccount (tag 308)
//   - EthSignRequest (tag 401), EthSignature (tag 402)
//   - SolSignRequest (tag 501), SolSignature (tag 502)
//
// UR format:  ur:{type}/{cbor-base58}
//   where cbor-base58 = base58(CBOR(tagged_data))
// ═══════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────
// CBOR tag constants
// ───────────────────────────────────────────────────────────────────────────

/// CBOR semantic tags defined by EIP-4527 / Blockchain Commons UR spec.
class EIP4527Tags {
  EIP4527Tags._();

  static const int cryptoHDKey = 303;
  static const int cryptoKeypath = 304;
  static const int cryptoCoinInfo = 305;
  static const int cryptoECKey = 306;
  static const int cryptoAccount = 308;
  static const int cryptoPSBT = 310;

  static const int ethSignRequest = 401;
  static const int ethSignature = 402;

  static const int solSignRequest = 501;
  static const int solSignature = 502;

  /// Map tag → UR type string.
  static const Map<int, String> _tagToType = {
    303: 'crypto-hdkey',
    304: 'crypto-keypath',
    305: 'crypto-coin-info',
    306: 'crypto-eckey',
    308: 'crypto-account',
    310: 'crypto-psbt',
    401: 'eth-sign-request',
    402: 'eth-signature',
    501: 'sol-sign-request',
    502: 'sol-signature',
  };

  /// Map UR type string → tag.
  static final Map<String, int> _typeToTag =
      _tagToType.map((k, v) => MapEntry(v, k));
}

// ───────────────────────────────────────────────────────────────────────────
// CryptoKeypath — BIP-32 / SLIP-10 derivation path (tag 304)
// ───────────────────────────────────────────────────────────────────────────

/// Represents a BIP-32 key derivation path.
///
/// Components are integers with the hardened bit (0x80000000) set
/// for hardened derivations.
class CryptoKeypath {
  /// Derivation path components (e.g., [0x8000002C, 0x8000003C, ...]).
  final List<int> components;

  /// Optional source fingerprint (from parent public key hash).
  final List<int>? sourceFingerprint;

  /// Optional depth (number of derivation steps).
  final int? depth;

  const CryptoKeypath({
    required this.components,
    this.sourceFingerprint,
    this.depth,
  });

  /// Get the source fingerprint as a hex string.
  String? get sourceFingerprintHex {
    if (sourceFingerprint == null) return null;
    return Hex.encode(Uint8List.fromList(sourceFingerprint!));
  }

  // ── Factory methods ────────────────────────────────────────────────

  /// Parse a derivation path string like "m/44'/60'/0'/0/0".
  factory CryptoKeypath.fromPath(String path) {
    final parts = path.split('/');
    final components = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part == 'm') continue;
      if (part.endsWith("'")) {
        final num = int.parse(part.substring(0, part.length - 1));
        components.add(0x80000000 | num);
      } else if (part.endsWith('h') || part.endsWith('H')) {
        final num =
            int.parse(part.substring(0, part.length - 1));
        components.add(0x80000000 | num);
      } else {
        components.add(int.parse(part));
      }
    }
    return CryptoKeypath(
      components: components,
      depth: components.length,
    );
  }

  /// Create from raw component list.
  factory CryptoKeypath.fromComponents(List<int> components) {
    return CryptoKeypath(
      components: List<int>.from(components),
      depth: components.length,
    );
  }

  // ── Serialization ─────────────────────────────────────────────────

  /// Format as a derivation path string.
  String toPath() {
    final parts = <String>['m'];
    for (final c in components) {
      if ((c & 0x80000000) != 0) {
        parts.add("${c & 0x7FFFFFFF}'");
      } else {
        parts.add('$c');
      }
    }
    return parts.join('/');
  }

  /// Convert to CBOR map (for use within other CBOR structures).
  Map<int, dynamic> toCborMap() {
    final map = <int, dynamic>{
      1: components,
    };
    if (sourceFingerprint != null) {
      map[2] = Uint8List.fromList(sourceFingerprint!);
    }
    if (depth != null) {
      map[3] = depth;
    }
    return map;
  }

  @override
  String toString() => 'CryptoKeypath(${toPath()})';
}

// ───────────────────────────────────────────────────────────────────────────
// CryptoCoinInfo — SLIP-44 coin type (tag 305)
// ───────────────────────────────────────────────────────────────────────────

/// SLIP-44 coin type information.
class CryptoCoinInfo {
  /// SLIP-44 coin type (e.g., 60 for ETH, 501 for SOL).
  final int type;

  /// Network indicator: 0 = mainnet, 1 = testnet.
  final int? network;

  const CryptoCoinInfo({required this.type, this.network});

  /// Mainnet coin info.
  factory CryptoCoinInfo.mainnet(int type) =>
      CryptoCoinInfo(type: type, network: 0);

  /// Testnet coin info.
  factory CryptoCoinInfo.testnet(int type) =>
      CryptoCoinInfo(type: type, network: 1);

  /// Convert to CBOR map.
  Map<int, dynamic> toCborMap() {
    final map = <int, dynamic>{1: type};
    if (network != null) map[2] = network;
    return map;
  }

  /// SLIP-44 coin type constants.
  static const int eth = 60;
  static const int sol = 501;
  static const int btc = 0;
  static const int trx = 195;
  static const int sui = 784;

  @override
  String toString() =>
      'CryptoCoinInfo(type: $type${network != null ? ", network: $network" : ""})';
}

// ───────────────────────────────────────────────────────────────────────────
// CryptoHDKey — BIP-32 HD key (tag 303)
// ───────────────────────────────────────────────────────────────────────────

/// BIP-32 Hierarchical Deterministic key.
class CryptoHDKey {
  /// Whether this is a master key.
  final bool isMaster;

  /// Key data (public or private key bytes) as hex.
  final String keyData;

  /// Optional chain code (32 bytes hex).
  final String? chainCode;

  /// Origin keypath (how this key was derived from master).
  final CryptoKeypath? origin;

  /// Children keypath (derivation restrictions for child keys).
  final CryptoKeypath? children;

  /// Optional parent fingerprint (4 bytes).
  final List<int>? parentFingerprint;

  /// Optional human-readable name.
  final String? name;

  /// Optional note / memo.
  final String? note;

  const CryptoHDKey({
    this.isMaster = false,
    required this.keyData,
    this.chainCode,
    this.origin,
    this.children,
    this.parentFingerprint,
    this.name,
    this.note,
  });

  /// Convert to tagged CBOR bytes (tag 303).
  Uint8List toCborBytes() {
    final map = toCborMap();
    return AirGapProtocol.cborTagEncode(EIP4527Tags.cryptoHDKey, map);
  }

  /// Convert to CBOR map.
  Map<int, dynamic> toCborMap() {
    final map = <int, dynamic>{
      2: Hex.decode(keyData),
    };
    if (isMaster) {
      map[1] = true;
    }
    if (chainCode != null) {
      map[3] = Hex.decode(chainCode!);
    }
    if (origin != null) {
      map[4] = origin!.toCborMap();
    }
    if (children != null) {
      map[5] = children!.toCborMap();
    }
    if (parentFingerprint != null) {
      map[6] = Uint8List.fromList(parentFingerprint!);
    }
    if (name != null) {
      map[7] = name;
    }
    if (note != null) {
      map[8] = note;
    }
    return map;
  }

  /// Create from decoded CBOR map.
  factory CryptoHDKey.fromCborMap(Map<dynamic, dynamic> map) {
    return CryptoHDKey(
      isMaster: map[1] == true,
      keyData: Hex.encode(map[2] as Uint8List),
      chainCode: map[3] != null
          ? Hex.encode(map[3] as Uint8List)
          : null,
      origin: map[4] != null
          ? CryptoKeypath.fromComponents(
              (map[4][1] as List).cast<int>())
          : null,
      children: map[5] != null
          ? CryptoKeypath.fromComponents(
              (map[5][1] as List).cast<int>())
          : null,
      parentFingerprint: map[6] != null
          ? (map[6] as Uint8List).toList()
          : null,
      name: map[7] as String?,
      note: map[8] as String?,
    );
  }

  @override
  String toString() =>
      'CryptoHDKey(isMaster: $isMaster, key: ${keyData.substring(0, _min(8, keyData.length))}...)';

  static int _min(int a, int b) => a < b ? a : b;
}

// ───────────────────────────────────────────────────────────────────────────
// CryptoAccount — Account container (tag 308)
// ───────────────────────────────────────────────────────────────────────────

/// A crypto account containing master fingerprint and output descriptors.
class CryptoAccount {
  /// Master key fingerprint (4 bytes).
  final List<int> masterFingerprint;

  /// Output descriptors (HD keys for this account).
  final List<CryptoHDKey> outputDescriptors;

  const CryptoAccount({
    required this.masterFingerprint,
    this.outputDescriptors = const [],
  });

  /// Convert to tagged CBOR bytes (tag 308).
  Uint8List toCborBytes() {
    final map = toCborMap();
    return AirGapProtocol.cborTagEncode(EIP4527Tags.cryptoAccount, map);
  }

  /// Convert to CBOR map.
  Map<int, dynamic> toCborMap() {
    return {
      1: Uint8List.fromList(masterFingerprint),
      2: outputDescriptors.map((d) => d.toCborMap()).toList(),
    };
  }

  /// Create from decoded CBOR map.
  factory CryptoAccount.fromCborMap(Map<dynamic, dynamic> map) {
    final descriptors = (map[2] as List)
        .map((d) => CryptoHDKey.fromCborMap(d as Map<dynamic, dynamic>))
        .toList();
    return CryptoAccount(
      masterFingerprint: (map[1] as Uint8List).toList(),
      outputDescriptors: descriptors,
    );
  }

  /// Get master fingerprint as hex string.
  String get masterFingerprintHex =>
      Hex.encode(Uint8List.fromList(masterFingerprint));

  @override
  String toString() =>
      'CryptoAccount(fp: $masterFingerprintHex, descriptors: ${outputDescriptors.length})';
}

// ───────────────────────────────────────────────────────────────────────────
// EthSignRequest — Ethereum signing request (tag 401)
// ───────────────────────────────────────────────────────────────────────────

/// Ethereum transaction / message signing request.
class EthSignRequest {
  /// Request identifier (UUID bytes, 16 bytes).
  final List<int> requestId;

  /// Data to sign — keccak256 hash of the transaction or message.
  final Uint8List signData;

  /// Derivation path for the signing key.
  final String derivationPath;

  /// Data type: 1=transaction, 2=typed_data, 3=personal_message, 4=typed_transaction.
  final int dataType;

  /// Chain ID (optional, for replay protection).
  final int? chainId;

  /// Optional origin HD key info.
  final CryptoHDKey? origin;

  /// Optional requesting address.
  final List<int>? address;

  const EthSignRequest({
    required this.requestId,
    required this.signData,
    required this.derivationPath,
    this.dataType = 1,
    this.chainId,
    this.origin,
    this.address,
  });

  /// Data type constants.
  static const int typeTransaction = 1;
  static const int typeTypedData = 2;
  static const int typePersonalMessage = 3;
  static const int typeTypedTransaction = 4;

  /// Convert to tagged CBOR bytes (tag 401).
  Uint8List toCborBytes() {
    final map = toCborMap();
    return AirGapProtocol.cborTagEncode(EIP4527Tags.ethSignRequest, map);
  }

  /// Convert to CBOR map.
  Map<int, dynamic> toCborMap() {
    final map = <int, dynamic>{
      1: Uint8List.fromList(requestId),
      2: signData,
      3: dataType,
      4: CryptoKeypath.fromPath(derivationPath).toCborMap(),
    };
    if (chainId != null) {
      map[5] = chainId;
    }
    if (address != null) {
      map[6] = Uint8List.fromList(address!);
    }
    if (origin != null) {
      map[7] = origin!.toCborMap();
    }
    return map;
  }

  /// Create from decoded CBOR map.
  factory EthSignRequest.fromCborMap(Map<dynamic, dynamic> map) {
    final keypath = CryptoKeypath.fromComponents(
        (map[4][1] as List).cast<int>());
    return EthSignRequest(
      requestId: (map[1] as Uint8List).toList(),
      signData: map[2] as Uint8List,
      dataType: map[3] as int,
      derivationPath: keypath.toPath(),
      chainId: map[5] as int?,
      address: map[6] != null
          ? (map[6] as Uint8List).toList()
          : null,
      origin: map[7] != null
          ? CryptoHDKey.fromCborMap(map[7] as Map<dynamic, dynamic>)
          : null,
    );
  }

  /// Build a CryptoAccount representing this request.
  CryptoAccount toCryptoAccount() {
    final fingerprint = _fingerprintFromRequestId(requestId);
    return CryptoAccount(
      masterFingerprint: fingerprint,
      outputDescriptors: origin != null ? [origin!] : [],
    );
  }

  static List<int> _fingerprintFromRequestId(List<int> requestId) {
    // Use first 4 bytes of requestId as a fingerprint approximation
    if (requestId.length >= 4) {
      return requestId.sublist(0, 4);
    }
    return List<int>.filled(4, 0);
  }

  /// Request ID as hex string.
  String get requestIdHex => Hex.encode(Uint8List.fromList(requestId));

  @override
  String toString() =>
      'EthSignRequest(id: $requestIdHex, path: $derivationPath, type: $dataType)';
}

// ───────────────────────────────────────────────────────────────────────────
// EthSignature — Ethereum signature response (tag 402)
// ───────────────────────────────────────────────────────────────────────────

/// Ethereum ECDSA signature response.
class EthSignature {
  /// Request identifier, echoed from the request.
  final List<int> requestId;

  /// 65-byte ECDSA signature (r + s + v).
  final Uint8List signature;

  const EthSignature({
    required this.requestId,
    required this.signature,
  });

  /// Convert to tagged CBOR bytes (tag 402).
  Uint8List toCborBytes() {
    final map = toCborMap();
    return AirGapProtocol.cborTagEncode(EIP4527Tags.ethSignature, map);
  }

  /// Convert to CBOR map.
  Map<int, dynamic> toCborMap() {
    return {
      1: Uint8List.fromList(requestId),
      2: signature,
    };
  }

  /// Create from decoded CBOR map.
  factory EthSignature.fromCborMap(Map<dynamic, dynamic> map) {
    return EthSignature(
      requestId: (map[1] as Uint8List).toList(),
      signature: map[2] as Uint8List,
    );
  }

  /// Hex-encoded signature.
  String get signatureHex => Hex.encode(signature);

  /// Request ID as hex.
  String get requestIdHex => Hex.encode(Uint8List.fromList(requestId));

  @override
  String toString() =>
      'EthSignature(id: $requestIdHex, sig: ${signatureHex.substring(0, _min(16, signatureHex.length))}...)';

  static int _min(int a, int b) => a < b ? a : b;
}

// ───────────────────────────────────────────────────────────────────────────
// SolSignRequest — Solana signing request (tag 501)
// ───────────────────────────────────────────────────────────────────────────

/// Solana message signing request.
class SolSignRequest {
  /// Request identifier (UUID bytes).
  final List<int> requestId;

  /// Message data to sign (exact bytes).
  final Uint8List signData;

  /// Derivation path for the signing key.
  final String derivationPath;

  /// Optional origin HD key info.
  final CryptoHDKey? origin;

  /// Optional requesting address.
  final List<int>? address;

  const SolSignRequest({
    required this.requestId,
    required this.signData,
    required this.derivationPath,
    this.origin,
    this.address,
  });

  /// Convert to tagged CBOR bytes (tag 501).
  Uint8List toCborBytes() {
    final map = toCborMap();
    return AirGapProtocol.cborTagEncode(EIP4527Tags.solSignRequest, map);
  }

  /// Convert to CBOR map.
  Map<int, dynamic> toCborMap() {
    final map = <int, dynamic>{
      1: Uint8List.fromList(requestId),
      2: signData,
      3: CryptoKeypath.fromPath(derivationPath).toCborMap(),
    };
    if (address != null) {
      map[4] = Uint8List.fromList(address!);
    }
    if (origin != null) {
      map[5] = origin!.toCborMap();
    }
    return map;
  }

  /// Create from decoded CBOR map.
  factory SolSignRequest.fromCborMap(Map<dynamic, dynamic> map) {
    final keypath = CryptoKeypath.fromComponents(
        (map[3][1] as List).cast<int>());
    return SolSignRequest(
      requestId: (map[1] as Uint8List).toList(),
      signData: map[2] as Uint8List,
      derivationPath: keypath.toPath(),
      address: map[4] != null
          ? (map[4] as Uint8List).toList()
          : null,
      origin: map[5] != null
          ? CryptoHDKey.fromCborMap(map[5] as Map<dynamic, dynamic>)
          : null,
    );
  }

  String get requestIdHex => Hex.encode(Uint8List.fromList(requestId));

  @override
  String toString() =>
      'SolSignRequest(id: $requestIdHex, path: $derivationPath)';
}

// ───────────────────────────────────────────────────────────────────────────
// SolSignature — Solana Ed25519 signature response (tag 502)
// ───────────────────────────────────────────────────────────────────────────

/// Solana Ed25519 signature response.
class SolSignature {
  /// Request identifier, echoed from the request.
  final List<int> requestId;

  /// 64-byte Ed25519 signature.
  final Uint8List signature;

  const SolSignature({
    required this.requestId,
    required this.signature,
  });

  /// Convert to tagged CBOR bytes (tag 502).
  Uint8List toCborBytes() {
    final map = toCborMap();
    return AirGapProtocol.cborTagEncode(EIP4527Tags.solSignature, map);
  }

  /// Convert to CBOR map.
  Map<int, dynamic> toCborMap() {
    return {
      1: Uint8List.fromList(requestId),
      2: signature,
    };
  }

  /// Create from decoded CBOR map.
  factory SolSignature.fromCborMap(Map<dynamic, dynamic> map) {
    return SolSignature(
      requestId: (map[1] as Uint8List).toList(),
      signature: map[2] as Uint8List,
    );
  }

  /// Hex-encoded signature.
  String get signatureHex => Hex.encode(signature);

  /// Request ID as hex.
  String get requestIdHex => Hex.encode(Uint8List.fromList(requestId));

  @override
  String toString() =>
      'SolSignature(id: $requestIdHex)';
}

// ═══════════════════════════════════════════════════════════════════════════
// UREncoder — encode/decode UR strings
// ═══════════════════════════════════════════════════════════════════════════

/// Encodes and decodes UR (Uniform Resource) strings per EIP-4527.
///
/// UR format: `ur:{type}/{cbor-base58}`
///   - type: the UR type string (e.g., "crypto-hdkey", "eth-sign-request")
///   - cbor-base58: CBOR bytes encoded as base58
class UREncoder {
  UREncoder._();

  // ── Low-level UR encode/decode ─────────────────────────────────────

  /// Encode a CBOR map to a UR string with the given [tag].
  ///
  /// The tag determines the UR type prefix.
  static String encode(Map<int, dynamic> cborMap, int tag) {
    final cborBytes = AirGapProtocol.cborTagEncode(tag, cborMap);
    final base58Str = AirGapProtocol.base58Encode(cborBytes);
    final type = EIP4527Tags._tagToType[tag] ?? 'unknown-$tag';
    return 'ur:$type/$base58Str';
  }

  /// Decode a UR string to a CBOR map.
  ///
  /// Returns a tuple of (tag, cborMap).
  /// Throws [FormatException] on invalid UR format.
  static ({int tag, Map<dynamic, dynamic> cborMap}) decode(String ur) {
    if (!ur.startsWith('ur:')) {
      throw FormatException('Invalid UR: missing "ur:" prefix');
    }

    final parts = ur.substring(3).split('/');
    if (parts.length < 2) {
      throw FormatException('Invalid UR: missing type/data separator');
    }

    final type = parts[0];
    // Data is the rest (may contain '/' in base58)
    final data = parts.sublist(1).join('/');

    final tag = EIP4527Tags._typeToTag[type];
    if (tag == null) {
      throw FormatException('Unknown UR type: $type');
    }

    final cborBytes = AirGapProtocol.base58Decode(data);
    final decoded = AirGapProtocol.cborDecode(cborBytes);

    if (decoded is! Map) {
      throw FormatException(
          'UR payload must be a CBOR map, got ${decoded.runtimeType}');
    }

    return (tag: tag, cborMap: decoded);
  }

  // ── High-level type-specific encode/decode ─────────────────────────

  /// Encode a [CryptoHDKey] to a UR string.
  static String encodeHDKey(CryptoHDKey key) {
    return encode(key.toCborMap(), EIP4527Tags.cryptoHDKey);
  }

  /// Encode a [CryptoAccount] to a UR string.
  static String encodeAccount(CryptoAccount account) {
    return encode(account.toCborMap(), EIP4527Tags.cryptoAccount);
  }

  /// Encode an [EthSignRequest] to a UR string.
  static String encodeEthSignRequest(EthSignRequest request) {
    return encode(request.toCborMap(), EIP4527Tags.ethSignRequest);
  }

  /// Encode an [EthSignature] to a UR string.
  static String encodeEthSignature(EthSignature signature) {
    return encode(signature.toCborMap(), EIP4527Tags.ethSignature);
  }

  /// Encode a [SolSignRequest] to a UR string.
  static String encodeSolSignRequest(SolSignRequest request) {
    return encode(request.toCborMap(), EIP4527Tags.solSignRequest);
  }

  /// Encode a [SolSignature] to a UR string.
  static String encodeSolSignature(SolSignature signature) {
    return encode(signature.toCborMap(), EIP4527Tags.solSignature);
  }

  /// Decode a UR string to an [EthSignRequest].
  static EthSignRequest decodeEthSignRequest(String ur) {
    final decoded = decode(ur);
    if (decoded.tag != EIP4527Tags.ethSignRequest) {
      throw FormatException(
          'Expected eth-sign-request (tag ${EIP4527Tags.ethSignRequest}), '
          'got tag ${decoded.tag}');
    }
    return EthSignRequest.fromCborMap(decoded.cborMap);
  }

  /// Decode a UR string to an [EthSignature].
  static EthSignature decodeEthSignature(String ur) {
    final decoded = decode(ur);
    if (decoded.tag != EIP4527Tags.ethSignature) {
      throw FormatException(
          'Expected eth-signature (tag ${EIP4527Tags.ethSignature}), '
          'got tag ${decoded.tag}');
    }
    return EthSignature.fromCborMap(decoded.cborMap);
  }

  /// Decode a UR string to a [SolSignRequest].
  static SolSignRequest decodeSolSignRequest(String ur) {
    final decoded = decode(ur);
    if (decoded.tag != EIP4527Tags.solSignRequest) {
      throw FormatException(
          'Expected sol-sign-request (tag ${EIP4527Tags.solSignRequest}), '
          'got tag ${decoded.tag}');
    }
    return SolSignRequest.fromCborMap(decoded.cborMap);
  }

  /// Decode a UR string to a [SolSignature].
  static SolSignature decodeSolSignature(String ur) {
    final decoded = decode(ur);
    if (decoded.tag != EIP4527Tags.solSignature) {
      throw FormatException(
          'Expected sol-signature (tag ${EIP4527Tags.solSignature}), '
          'got tag ${decoded.tag}');
    }
    return SolSignature.fromCborMap(decoded.cborMap);
  }

  /// Generic decode to a [CryptoHDKey].
  static CryptoHDKey decodeHDKey(String ur) {
    final decoded = decode(ur);
    if (decoded.tag != EIP4527Tags.cryptoHDKey) {
      throw FormatException(
          'Expected crypto-hdkey (tag ${EIP4527Tags.cryptoHDKey}), '
          'got tag ${decoded.tag}');
    }
    return CryptoHDKey.fromCborMap(decoded.cborMap);
  }

  /// Generic decode to a [CryptoAccount].
  static CryptoAccount decodeAccount(String ur) {
    final decoded = decode(ur);
    if (decoded.tag != EIP4527Tags.cryptoAccount) {
      throw FormatException(
          'Expected crypto-account (tag ${EIP4527Tags.cryptoAccount}), '
          'got tag ${decoded.tag}');
    }
    return CryptoAccount.fromCborMap(decoded.cborMap);
  }
}
