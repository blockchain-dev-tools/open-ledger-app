import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════════════════════
// AirGap IAC Protocol v3 — QR-code-based offline signing protocol.
//
// Encoding pipeline: JSON → CBOR → base58check
// (deflate step is skipped in this prototype; TODO: add zlib deflate)
//
// Includes self-contained implementations of:
//   - SHA-256 (pure Dart, 32-bit arithmetic)
//   - Base58 / Base58Check
//   - Minimal CBOR encoder + decoder (no external deps)
// ═══════════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────────
// SHA-256 — pure Dart implementation (no external deps)
// ───────────────────────────────────────────────────────────────────────────

class _Sha256 {
  _Sha256._();

  // Initial hash values H[0..7] — first 32 bits of fractional parts
  // of the square roots of the first 8 primes.
  static const _h0 = [
    0x6a09e667, 0xbb67ae85, 0x3c6efe67, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  // Round constants K[0..63] — first 32 bits of fractional parts
  // of the cube roots of the first 64 primes.
  static const _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  /// Compute SHA-256 hash of [data], returns 32-byte digest.
  static Uint8List hash(Uint8List data) {
    // Padding
    final ml = data.length * 8; // message length in bits
    // k = minimum number of zero bits such that (ml + 1 + k) % 512 == 448
    // After the 1 bit, we need the total bits to be 448 mod 512.
    // Total bits before padding = ml
    // We need (ml + 1 + k + 64) % 512 == 0
    // So (ml + 1 + k) % 512 == 448
    // k = (448 - (ml + 1)) % 512  (but if negative, add 512)
    var k = (448 - (ml + 1)) % 512;
    if (k < 0) k += 512;
    // k is in bits; convert to bytes: k ~/ 8 zero bytes
    final zeroBytes = k ~/ 8;

    // Total padded bytes: original + 1 byte for 0x80 + zeroBytes + 8 bytes for length
    final paddedLen = data.length + 1 + zeroBytes + 8;
    final padded = Uint8List(paddedLen);
    padded.setRange(0, data.length, data);
    padded[data.length] = 0x80; // append '1' bit followed by 7 zero bits
    // Append 64-bit big-endian length at the end
    for (int i = 0; i < 8; i++) {
      padded[paddedLen - 1 - i] = ((ml >> (i * 8)) & 0xFF);
    }

    // Process 512-bit (64-byte) chunks
    final h = List<int>.from(_h0);
    for (int offset = 0; offset < paddedLen; offset += 64) {
      _processChunk(padded, offset, h);
    }

    // Produce final 32-byte digest
    final digest = Uint8List(32);
    for (int i = 0; i < 8; i++) {
      final v = h[i];
      digest[i * 4] = (v >> 24) & 0xFF;
      digest[i * 4 + 1] = (v >> 16) & 0xFF;
      digest[i * 4 + 2] = (v >> 8) & 0xFF;
      digest[i * 4 + 3] = v & 0xFF;
    }
    return digest;
  }

  /// Compute SHA-256d (double SHA-256) of [data].
  static Uint8List hash256d(Uint8List data) {
    return hash(hash(data));
  }

  static int _rotr(int x, int n) {
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;
  }

  static void _processChunk(Uint8List chunk, int offset, List<int> h) {
    final w = List<int>.filled(64, 0);

    // First 16 words: copy from chunk (big-endian)
    for (int i = 0; i < 16; i++) {
      final base = offset + i * 4;
      w[i] = (chunk[base] << 24) |
          (chunk[base + 1] << 16) |
          (chunk[base + 2] << 8) |
          chunk[base + 3];
    }

    // Extend to 64 words
    for (int i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }

    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];

    for (int i = 0; i < 64; i++) {
      final sigma1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final temp1 = (hh + sigma1 + ch + _k[i] + w[i]) & 0xFFFFFFFF;
      final sigma0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sigma0 + maj) & 0xFFFFFFFF;

      hh = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xFFFFFFFF;
    }

    h[0] = (h[0] + a) & 0xFFFFFFFF;
    h[1] = (h[1] + b) & 0xFFFFFFFF;
    h[2] = (h[2] + c) & 0xFFFFFFFF;
    h[3] = (h[3] + d) & 0xFFFFFFFF;
    h[4] = (h[4] + e) & 0xFFFFFFFF;
    h[5] = (h[5] + f) & 0xFFFFFFFF;
    h[6] = (h[6] + g) & 0xFFFFFFFF;
    h[7] = (h[7] + hh) & 0xFFFFFFFF;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Base58 / Base58Check — self-contained (no external deps)
// ───────────────────────────────────────────────────────────────────────────

class _Base58 {
  _Base58._();

  static const _alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// Encode [bytes] as base58 string.
  static String encode(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    // Count leading zeros
    int leadingZeros = 0;
    while (leadingZeros < bytes.length && bytes[leadingZeros] == 0) {
      leadingZeros++;
    }

    // Convert bytes to big integer
    BigInt value = BigInt.zero;
    for (int i = leadingZeros; i < bytes.length; i++) {
      value = (value << 8) | BigInt.from(bytes[i]);
    }

    // Build base58 string (least significant digit first)
    final result = StringBuffer();
    final big58 = BigInt.from(58);
    while (value > BigInt.zero) {
      final rem = (value % big58).toInt();
      result.write(_alphabet[rem]);
      value = value ~/ big58;
    }

    // Prepend '1' for each leading zero byte
    final prefix = '1' * leadingZeros;
    return prefix + result.toString().split('').reversed.join();
  }

  /// Decode base58 [encoded] string to bytes.
  static Uint8List decode(String encoded) {
    if (encoded.isEmpty) return Uint8List(0);

    // Count leading '1's
    int leadingOnes = 0;
    while (leadingOnes < encoded.length && encoded[leadingOnes] == '1') {
      leadingOnes++;
    }

    // Convert base58 to big integer
    BigInt value = BigInt.zero;
    final big58 = BigInt.from(58);
    for (int i = leadingOnes; i < encoded.length; i++) {
      final idx = _alphabet.indexOf(encoded[i]);
      if (idx < 0) {
        throw FormatException('Invalid base58 character: ${encoded[i]}');
      }
      value = value * big58 + BigInt.from(idx);
    }

    // Convert big integer to bytes
    final bytes = <int>[];
    while (value > BigInt.zero) {
      bytes.insert(0, (value & BigInt.from(0xFF)).toInt());
      value = value >> 8;
    }

    // Prepend zero bytes for each leading '1'
    final result = Uint8List(leadingOnes + bytes.length);
    result.setRange(leadingOnes, result.length, bytes);
    return result;
  }
}

/// Base58Check: base58 encoding with SHA-256d checksum prefix.
class _Base58Check {
  _Base58Check._();

  /// Encode [data] with 4-byte SHA-256d checksum.
  static String encode(Uint8List data) {
    final checksum = _Sha256.hash256d(data);
    final payload = Uint8List(data.length + 4);
    payload.setRange(0, data.length, data);
    payload.setRange(data.length, data.length + 4, checksum);
    return _Base58.encode(payload);
  }

  /// Decode base58check-encoded string, verifying checksum.
  /// Returns decoded data, or throws [FormatException] on checksum failure.
  static Uint8List decode(String encoded) {
    final decoded = _Base58.decode(encoded);
    if (decoded.length < 4) {
      throw FormatException('Base58Check payload too short');
    }
    final data = Uint8List.sublistView(decoded, 0, decoded.length - 4);
    final checksum = Uint8List.sublistView(decoded, decoded.length - 4);
    final computed = _Sha256.hash256d(data);
    final computedPrefix = Uint8List.sublistView(computed, 0, 4);
    if (!_bytesEqual(computedPrefix, checksum)) {
      throw FormatException('Base58Check checksum mismatch');
    }
    return data;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Minimal CBOR encoder + decoder (RFC 7049 subset, no external deps)
//
// Handles types needed for AirGap + EIP-4527:
//   Type 0: unsigned integer
//   Type 2: byte string
//   Type 3: text string
//   Type 4: array
//   Type 5: map
//   Type 6: semantic tag
// ───────────────────────────────────────────────────────────────────────────

class _MinimalCbor {
  _MinimalCbor._();

  // ═══════════════════════════════════════════════════════════════════
  // Encoder
  // ═══════════════════════════════════════════════════════════════════

  /// Encode a Dart value into CBOR bytes.
  ///
  /// Supported types:
  /// - `int` → unsigned integer (type 0)
  /// - `Uint8List` → byte string (type 2)
  /// - `String` → text string (type 3)
  /// - `List` → array (type 4)
  /// - `Map` → map (type 5)
  /// - `_CborTag` → semantic tag (type 6)
  static Uint8List encode(dynamic value) {
    final buf = <int>[];
    _encodeValue(value, buf);
    return Uint8List.fromList(buf);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Decoder
  // ═══════════════════════════════════════════════════════════════════

  /// Decode CBOR bytes into a Dart value.
  static dynamic decode(Uint8List data) {
    final reader = _CborReader(data);
    return reader._readValue();
  }

  // ── Internal encoder ──────────────────────────────────────────────

  static void _encodeValue(dynamic value, List<int> buf) {
    if (value is int) {
      _encodeUint(value, buf, 0);
    } else if (value is Uint8List || value is List<int>) {
      final bytes = value is Uint8List
          ? value
          : Uint8List.fromList(value as List<int>);
      _encodeHead(2, bytes.length, buf);
      buf.addAll(bytes);
    } else if (value is String) {
      final utf8Bytes = _utf8Encode(value);
      _encodeHead(3, utf8Bytes.length, buf);
      buf.addAll(utf8Bytes);
    } else if (value is Map) {
      // CBOR requires maps sorted by key encoding, but for simplicity
      // we encode as-is. AirGap typically uses string keys in order.
      _encodeHead(5, value.length, buf);
      value.forEach((k, v) {
        // Keys are always strings in AirGap
        _encodeValue(k.toString(), buf);
        _encodeValue(v, buf);
      });
    } else if (value is List) {
      _encodeHead(4, value.length, buf);
      for (final item in value) {
        _encodeValue(item, buf);
      }
    } else if (value is _CborTag) {
      _encodeHead(6, value.tag, buf);
      _encodeValue(value.value, buf);
    } else {
      throw ArgumentError('Unsupported CBOR type: ${value.runtimeType}');
    }
  }

  /// Encode a major type head (3-bit type + 5-bit argument or length prefix).
  static void _encodeHead(int majorType, int value, List<int> buf) {
    if (value < 24) {
      buf.add((majorType << 5) | value);
    } else if (value < 256) {
      buf.add((majorType << 5) | 24);
      buf.add(value);
    } else if (value < 65536) {
      buf.add((majorType << 5) | 25);
      buf.add((value >> 8) & 0xFF);
      buf.add(value & 0xFF);
    } else if (value < 4294967296) {
      buf.add((majorType << 5) | 26);
      buf.add((value >> 24) & 0xFF);
      buf.add((value >> 16) & 0xFF);
      buf.add((value >> 8) & 0xFF);
      buf.add(value & 0xFF);
    } else {
      // 64-bit
      buf.add((majorType << 5) | 27);
      buf.add((value >> 56) & 0xFF);
      buf.add((value >> 48) & 0xFF);
      buf.add((value >> 40) & 0xFF);
      buf.add((value >> 32) & 0xFF);
      buf.add((value >> 24) & 0xFF);
      buf.add((value >> 16) & 0xFF);
      buf.add((value >> 8) & 0xFF);
      buf.add(value & 0xFF);
    }
  }

  static void _encodeUint(int value, List<int> buf, int majorType) {
    _encodeHead(majorType, value, buf);
  }

  /// Minimal UTF-8 encoder.
  static List<int> _utf8Encode(String s) {
    final result = <int>[];
    for (int i = 0; i < s.length; i++) {
      final cp = s.codeUnitAt(i);
      if (cp < 0x80) {
        result.add(cp);
      } else if (cp < 0x800) {
        result.add(0xC0 | (cp >> 6));
        result.add(0x80 | (cp & 0x3F));
      } else if (cp < 0xD800 || cp > 0xDFFF) {
        result.add(0xE0 | (cp >> 12));
        result.add(0x80 | ((cp >> 6) & 0x3F));
        result.add(0x80 | (cp & 0x3F));
      } else {
        // Surrogate pair
        if (i + 1 < s.length) {
          final low = s.codeUnitAt(i + 1);
          final combined = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
          result.add(0xF0 | (combined >> 18));
          result.add(0x80 | ((combined >> 12) & 0x3F));
          result.add(0x80 | ((combined >> 6) & 0x3F));
          result.add(0x80 | (combined & 0x3F));
          i++; // skip low surrogate
        }
      }
    }
    return result;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// CBOR reader (decoder)
// ───────────────────────────────────────────────────────────────────────────

class _CborReader {
  final Uint8List _data;
  int _pos = 0;

  _CborReader(this._data);

  dynamic _readValue() {
    if (_pos >= _data.length) {
      throw FormatException('Unexpected end of CBOR data');
    }
    final initial = _data[_pos++];
    final majorType = initial >> 5;
    final additional = initial & 0x1F;

    final arg = _readArgument(additional);

    switch (majorType) {
      case 0: // unsigned integer
        return arg;
      case 2: // byte string
        final bytes = _readExact(arg);
        return Uint8List.fromList(bytes);
      case 3: // text string
        final bytes = _readExact(arg);
        return _utf8Decode(bytes);
      case 4: // array
        final list = <dynamic>[];
        for (int i = 0; i < arg; i++) {
          list.add(_readValue());
        }
        return list;
      case 5: // map
        final map = <dynamic, dynamic>{};
        for (int i = 0; i < arg; i++) {
          final key = _readValue();
          final value = _readValue();
          map[key] = value;
        }
        return map;
      case 6: // semantic tag
        final value = _readValue();
        return _CborTag(arg, value);
      default:
        throw FormatException(
            'Unsupported CBOR major type: $majorType at position ${_pos - 1}');
    }
  }

  int _readArgument(int additional) {
    if (additional < 24) return additional;
    switch (additional) {
      case 24:
        return _readUint8();
      case 25:
        return (_readUint8() << 8) | _readUint8();
      case 26:
        return (_readUint8() << 24) |
            (_readUint8() << 16) |
            (_readUint8() << 8) |
            _readUint8();
      case 27:
        return (_readUint8() << 56) |
            (_readUint8() << 48) |
            (_readUint8() << 40) |
            (_readUint8() << 32) |
            (_readUint8() << 24) |
            (_readUint8() << 16) |
            (_readUint8() << 8) |
            _readUint8();
      default:
        throw FormatException(
            'Invalid CBOR additional info: $additional');
    }
  }

  int _readUint8() {
    if (_pos >= _data.length) {
      throw FormatException('Unexpected end of CBOR data');
    }
    return _data[_pos++];
  }

  List<int> _readExact(int length) {
    if (_pos + length > _data.length) {
      throw FormatException('Unexpected end of CBOR data');
    }
    final result = _data.sublist(_pos, _pos + length);
    _pos += length;
    return result;
  }

  /// Minimal UTF-8 decoder.
  static String _utf8Decode(List<int> bytes) {
    final sb = StringBuffer();
    int i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      int cp;
      int len;
      if ((b & 0x80) == 0) {
        cp = b;
        len = 1;
      } else if ((b & 0xE0) == 0xC0) {
        cp = b & 0x1F;
        len = 2;
      } else if ((b & 0xF0) == 0xE0) {
        cp = b & 0x0F;
        len = 3;
      } else if ((b & 0xF8) == 0xF0) {
        cp = b & 0x07;
        len = 4;
      } else {
        // Invalid, skip
        i++;
        continue;
      }
      if (i + len > bytes.length) break;
      for (int j = 1; j < len; j++) {
        cp = (cp << 6) | (bytes[i + j] & 0x3F);
      }
      sb.writeCharCode(cp);
      i += len;
    }
    return sb.toString();
  }
}

// ───────────────────────────────────────────────────────────────────────────
// CBOR tag wrapper — used by EIP-4527
// ───────────────────────────────────────────────────────────────────────────

/// Wraps a value with a CBOR semantic tag.
class _CborTag {
  final int tag;
  final dynamic value;
  const _CborTag(this.tag, this.value);
}

// ═══════════════════════════════════════════════════════════════════════════
// AirGap Protocol — message types, payloads, encode/decode
// ═══════════════════════════════════════════════════════════════════════════

/// AirGap IAC message types.
enum AirGapMessageType {
  accountShare,
  transactionSignRequest,
  transactionSignResponse,
  messageSignRequest,
  messageSignResponse;

  String get value {
    switch (this) {
      case AirGapMessageType.accountShare:
        return 'account_share';
      case AirGapMessageType.transactionSignRequest:
        return 'transaction_sign_request';
      case AirGapMessageType.transactionSignResponse:
        return 'transaction_sign_response';
      case AirGapMessageType.messageSignRequest:
        return 'message_sign_request';
      case AirGapMessageType.messageSignResponse:
        return 'message_sign_response';
    }
  }
}

/// Account share payload — sent from Vault to companion app.
class AirGapAccountShare {
  final String publicKey;
  final String derivationPath;
  final String masterFingerprint;
  final bool isExtendedPublicKey;

  const AirGapAccountShare({
    required this.publicKey,
    required this.derivationPath,
    required this.masterFingerprint,
    this.isExtendedPublicKey = false,
  });

  factory AirGapAccountShare.fromJson(Map<String, dynamic> json) {
    return AirGapAccountShare(
      publicKey: json['publicKey'] as String,
      derivationPath: json['derivationPath'] as String,
      masterFingerprint: json['masterFingerprint'] as String,
      isExtendedPublicKey: json['isExtendedPublicKey'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'publicKey': publicKey,
      'derivationPath': derivationPath,
      'masterFingerprint': masterFingerprint,
      'isExtendedPublicKey': isExtendedPublicKey,
    };
  }

  @override
  String toString() =>
      'AirGapAccountShare(path: $derivationPath, fp: $masterFingerprint)';
}

/// Transaction sign request — sent from companion app to Vault.
class AirGapSignRequest {
  /// Hex-encoded transaction payload (RLP for ETH, raw tx for others).
  final String transaction;

  final String publicKey;
  final String derivationPath;
  final String masterFingerprint;

  const AirGapSignRequest({
    required this.transaction,
    required this.publicKey,
    required this.derivationPath,
    required this.masterFingerprint,
  });

  factory AirGapSignRequest.fromJson(Map<String, dynamic> json) {
    return AirGapSignRequest(
      transaction: json['transaction'] as String,
      publicKey: json['publicKey'] as String,
      derivationPath: json['derivationPath'] as String,
      masterFingerprint: json['masterFingerprint'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transaction': transaction,
      'publicKey': publicKey,
      'derivationPath': derivationPath,
      'masterFingerprint': masterFingerprint,
    };
  }

  @override
  String toString() =>
      'AirGapSignRequest(path: $derivationPath, fp: $masterFingerprint)';
}

/// Signature response — sent from Vault back to companion app.
class AirGapSignResponse {
  /// Hex-encoded signature (65 bytes for ETH, 64 for Solana, etc.).
  final String signature;

  /// The request ID echoed back for correlation.
  final String? requestId;

  const AirGapSignResponse({
    required this.signature,
    this.requestId,
  });

  factory AirGapSignResponse.fromJson(Map<String, dynamic> json) {
    return AirGapSignResponse(
      signature: json['signature'] as String,
      requestId: json['requestId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'signature': signature,
      if (requestId != null) 'requestId': requestId,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AirGapProtocol — encode / decode / chunk
// ═══════════════════════════════════════════════════════════════════════════

/// AirGap IAC Protocol v3 encoder/decoder.
///
/// Pipeline: JSON → CBOR → base58check
/// (deflate step skipped; TODO: add zlib deflate for size reduction)
class AirGapProtocol {
  AirGapProtocol._();

  // ── Base58 helpers (public, used by EIP-4527) ──────────────────────

  /// Encode bytes as plain base58 (no checksum).
  static String base58Encode(Uint8List data) {
    return _Base58.encode(data);
  }

  /// Decode plain base58 string to bytes.
  static Uint8List base58Decode(String encoded) {
    return _Base58.decode(encoded);
  }

  // ── Base58check helpers (public, for AirGap protocol) ──────────────

  /// Encode bytes with base58check (SHA-256d checksum).
  static String base58CheckEncode(Uint8List data) {
    return _Base58Check.encode(data);
  }

  /// Decode base58check-encoded string, verifying checksum.
  static Uint8List base58CheckDecode(String encoded) {
    return _Base58Check.decode(encoded);
  }

  // ── CBOR helpers (public, for use by EIP-4527) ─────────────────────

  /// Encode a Dart value to CBOR bytes.
  static Uint8List cborEncode(dynamic value) {
    return _MinimalCbor.encode(value);
  }

  /// Decode CBOR bytes to a Dart value.
  static dynamic cborDecode(Uint8List data) {
    return _MinimalCbor.decode(data);
  }

  // ── Tagged CBOR — EIP-4527 uses tagged CBOR ────────────────────────

  /// Encode CBOR bytes with a semantic tag.
  static Uint8List cborTagEncode(int tag, dynamic value) {
    return _MinimalCbor.encode(_CborTag(tag, value));
  }

  // ── AirGap Protocol ────────────────────────────────────────────────

  /// Encode a JSON payload to AirGap base58check string.
  ///
  /// Pipeline: JSON → CBOR → base58check
  static String encode(Map<String, dynamic> payload) {
    final cborBytes = _MinimalCbor.encode(payload);
    return _Base58Check.encode(cborBytes);
  }

  /// Decode an AirGap base58check string to JSON payload.
  ///
  /// Pipeline: base58check → CBOR → JSON
  static Map<String, dynamic> decode(String encoded) {
    final cborBytes = _Base58Check.decode(encoded);
    final decoded = _MinimalCbor.decode(cborBytes);
    if (decoded is! Map) {
      throw FormatException(
          'AirGap payload must be a CBOR map, got ${decoded.runtimeType}');
    }
    // Convert all keys to String (CBOR may have int keys)
    return _toStringMap(decoded);
  }

  /// Chunk a large payload into multiple base58check strings.
  ///
  /// Each chunk is independently decodable with [chunkDecode].
  /// Splits CBOR bytes roughly evenly by [maxChunkSize] bytes.
  static List<String> chunkEncode(
      Map<String, dynamic> payload, int maxChunkSize) {
    final cborBytes = _MinimalCbor.encode(payload);
    final total = cborBytes.length;

    if (total <= maxChunkSize) {
      // Single chunk — prepend "0|" for single-chunk marker
      return [_Base58Check.encode(_withPrefix(0, 1, cborBytes))];
    }

    final chunkCount = (total / maxChunkSize).ceil();
    final chunks = <String>[];

    for (int i = 0; i < chunkCount; i++) {
      final start = i * maxChunkSize;
      final end = (start + maxChunkSize).clamp(0, total);
      final chunkData = Uint8List.sublistView(cborBytes, start, end);
      chunks.add(
          _Base58Check.encode(_withPrefix(i, chunkCount, chunkData)));
    }

    return chunks;
  }

  /// Combine chunked base58check strings back into the original payload.
  static Map<String, dynamic> chunkDecode(List<String> chunks) {
    if (chunks.isEmpty) {
      throw ArgumentError('No chunks provided');
    }

    final allBytes = <int>[];

    for (final chunk in chunks) {
      final data = _Base58Check.decode(chunk);
      if (data.length < 2) {
        throw FormatException('Chunk too short: missing prefix');
      }
      final seq = data[0];
      final totalCount = data[1];
      final payload = Uint8List.sublistView(data, 2);
      allBytes.addAll(payload);

      // Validate sequence
      if (seq >= totalCount) {
        throw FormatException(
            'Invalid chunk sequence $seq / $totalCount');
      }
    }

    // Validate total count consistency
    if (chunks.length > 1) {
      final firstData = _Base58Check.decode(chunks[0]);
      final totalFromChunks = firstData[1];
      if (chunks.length != totalFromChunks) {
        throw FormatException(
            'Chunk count mismatch: expected $totalFromChunks, got ${chunks.length}');
      }
    }

    final decoded = _MinimalCbor.decode(Uint8List.fromList(allBytes));
    if (decoded is! Map) {
      throw FormatException(
          'AirGap payload must be a CBOR map, got ${decoded.runtimeType}');
    }
    return _toStringMap(decoded);
  }

  // ── Internal helpers ───────────────────────────────────────────────

  /// Prepend chunk sequence info: [seq_byte, total_byte, ...data]
  static Uint8List _withPrefix(
      int seq, int total, Uint8List data) {
    final result = Uint8List(data.length + 2);
    result[0] = seq;
    result[1] = total;
    result.setRange(2, result.length, data);
    return result;
  }

  /// Convert a decoded CBOR map with potential non-String keys to all
  /// String keys (for JSON compatibility).
  static Map<String, dynamic> _toStringMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        result[key] = _toStringMap(value);
      } else if (value is Uint8List) {
        result[key] = _hexEncode(value);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Simple hex encoder (mirrors CryptoBridge.hexEncode).
  static String _hexEncode(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hex utility (public, available for import by other modules)
// ═══════════════════════════════════════════════════════════════════════════

/// Hex encode/decode utilities for bytes ↔ hex strings.
///
/// Used by both AirGap and EIP-4527 modules.
class Hex {
  Hex._();

  /// Encode bytes to lowercase hex string.
  static String encode(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Decode hex string to bytes.
  static Uint8List decode(String hex) {
    if (hex.length % 2 != 0) {
      throw ArgumentError('Invalid hex string (odd length)');
    }
    return Uint8List.fromList(List.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ));
  }
}
