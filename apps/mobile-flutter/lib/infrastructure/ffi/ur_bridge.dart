import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../core/interfaces/ur_codec.dart';
import '../../core/models/ur_qr.dart';
import 'crypto_bridge.dart';

// ── C signatures (see crates/open-ledger-ffi/src/ur.rs) ──────────────────

typedef _NewSessionC = Pointer<Void> Function();
typedef _NewSessionDart = Pointer<Void> Function();

typedef _FreeSessionC = Void Function(Pointer<Void>);
typedef _FreeSessionDart = void Function(Pointer<Void>);

typedef _ReceiveC = Pointer<FfiResult> Function(Pointer<Void>, Pointer<Utf8>);
typedef _ReceiveDart = Pointer<FfiResult> Function(Pointer<Void>, Pointer<Utf8>);

typedef _SessionResultC = Pointer<FfiResult> Function(Pointer<Void>);
typedef _SessionResultDart = Pointer<FfiResult> Function(Pointer<Void>);

typedef _String1C = Pointer<FfiResult> Function(Pointer<Utf8>);
typedef _String1Dart = Pointer<FfiResult> Function(Pointer<Utf8>);

typedef _String2C = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _String2Dart = Pointer<FfiResult> Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _EncodeSignatureC = Pointer<FfiResult> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Uint32,
);
typedef _EncodeSignatureDart = Pointer<FfiResult> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  int,
);

typedef _EncodeAccountC = Pointer<FfiResult> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Uint32,
  Uint32,
  Uint32,
);
typedef _EncodeAccountDart = Pointer<FfiResult> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  int,
  int,
  int,
);

typedef _FreeResultC = Void Function(Pointer<FfiResult>);
typedef _FreeResultDart = void Function(Pointer<FfiResult>);

/// [IUrCodec] 的 FFI 实现。
///
/// 与 [ChainHostBridge] 不同，这里**不**静默降级：二维码流程必须知道
/// 编解码是否真的可用，否则用户会对着一个永远收不满的进度条等 60 秒。
class UrBridge implements IUrCodec {
  UrBridge() {
    try {
      final lib = CryptoBridge.nativeLibrary;
      _newSessionBridge = lib.lookupFunction<_NewSessionC, _NewSessionDart>(
        'ur_session_new',
      );
      _freeSession = lib.lookupFunction<_FreeSessionC, _FreeSessionDart>(
        'ur_session_free',
      );
      _receiveBridge = lib.lookupFunction<_ReceiveC, _ReceiveDart>(
        'ur_session_receive',
      );
      _sessionResultBridge =
          lib.lookupFunction<_SessionResultC, _SessionResultDart>(
            'ur_session_result',
          );
      _parseBridge = lib.lookupFunction<_String1C, _String1Dart>(
        'ur_parse_eth_sign_request',
      );
      _signBridge = lib.lookupFunction<_String2C, _String2Dart>(
        'ur_sign_eth_request',
      );
      _encodeSignatureBridge =
          lib.lookupFunction<_EncodeSignatureC, _EncodeSignatureDart>(
            'ur_encode_eth_signature',
          );
      _encodeAccountBridge =
          lib.lookupFunction<_EncodeAccountC, _EncodeAccountDart>(
            'ur_encode_crypto_account',
          );
      _freeResult = lib.lookupFunction<_FreeResultC, _FreeResultDart>(
        'free_ffi_result',
      );
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  late final _NewSessionDart _newSessionBridge;
  late final _FreeSessionDart _freeSession;
  late final _ReceiveDart _receiveBridge;
  late final _SessionResultDart _sessionResultBridge;
  late final _String1Dart _parseBridge;
  late final _String2Dart _signBridge;
  late final _EncodeSignatureDart _encodeSignatureBridge;
  late final _EncodeAccountDart _encodeAccountBridge;
  late final _FreeResultDart _freeResult;

  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  IUrSession newSession() {
    _requireAvailable();
    final handle = _newSessionBridge();
    if (handle == nullptr) {
      throw const UrCodecException('Could not start a QR session');
    }
    return _UrSession(this, handle);
  }

  @override
  EthSignRequestView parseSignRequest(Uint8List cbor) {
    final json = _callString(
      (text) => _parseBridge(text),
      CryptoBridge.hexEncode(cbor),
    );
    final map = _decodeMap(json);
    return EthSignRequestView(
      requestIdHex: map['requestId'] as String?,
      dataType: _asInt(map['dataType']),
      chainId: map['chainId'] == null ? null : _asInt(map['chainId']),
      path: map['path'] as String? ?? '',
      address: map['address'] as String?,
      origin: map['origin'] as String?,
      signDataHex: map['signDataHex'] as String? ?? '',
      signingHashHex: map['signingHashHex'] as String? ?? '',
    );
  }

  @override
  EthSignResult signRequest(Uint8List cbor, String seedHex) {
    _requireAvailable();
    final cborText = _toNative(CryptoBridge.hexEncode(cbor));
    final seed = _toNative(seedHex);
    final String json;
    try {
      json = _read(_signBridge(cborText, seed));
    } finally {
      malloc.free(cborText);
      malloc.free(seed);
    }
    final map = _decodeMap(json);
    return EthSignResult(
      requestIdHex: map['requestId'] as String? ?? '',
      signature: CryptoBridge.hexToBytes(map['signatureHex'] as String? ?? ''),
      address: map['address'] as String? ?? '',
      addressMatches: map['addressMatches'] == true,
    );
  }

  @override
  List<String> encodeSignature({
    required String requestIdHex,
    required Uint8List signature,
    String? origin,
    int fragmentLength = 0,
  }) {
    final request = _toNative(requestIdHex);
    final signatureText = _toNative(CryptoBridge.hexEncode(signature));
    final originText = origin == null ? nullptr : _toNative(origin);
    try {
      final json = _read(_encodeSignatureBridge(
        request,
        signatureText,
        originText,
        fragmentLength,
      ));
      return _frames(json);
    } finally {
      malloc.free(request);
      malloc.free(signatureText);
      if (originText != nullptr) malloc.free(originText);
    }
  }

  @override
  CryptoAccountExport encodeAccount({
    required String seedHex,
    required String path,
    int count = 1,
    bool accountLevel = false,
    int fragmentLength = 0,
  }) {
    _requireAvailable();
    final seed = _toNative(seedHex);
    final pathText = _toNative(path);
    try {
      final json = _read(
        _encodeAccountBridge(
          seed,
          pathText,
          count,
          accountLevel ? 1 : 0,
          fragmentLength,
        ),
      );
      final map = _decodeMap(json);
      final addresses = map['addresses'];
      return CryptoAccountExport(
        frames: _frames(json),
        address: map['address'] as String? ?? '',
        addresses: addresses is List
            ? addresses.whereType<String>().toList(growable: false)
            : const [],
        path: map['path'] as String? ?? path,
      );
    } finally {
      malloc.free(seed);
      malloc.free(pathText);
    }
  }

  void _requireAvailable() {
    if (!_available) {
      throw const UrCodecException('QR codec is not available in this build');
    }
  }

  /// 单字符串入参的调用；`free_ffi_result` 由 [read] 负责。
  String _callString(
    Pointer<FfiResult> Function(Pointer<Utf8>) call,
    String argument,
  ) {
    _requireAvailable();
    final text = _toNative(argument);
    try {
      return _read(call(text));
    } finally {
      malloc.free(text);
    }
  }

  String _read(Pointer<FfiResult> result) {
    if (result == nullptr) {
      throw const UrCodecException('Native call returned no result');
    }
    final view = result.ref;
    final failed = view.errorCode != 0;
    final String data;
    final String error;
    if (failed) {
      error = view.errorMsg == nullptr
          ? 'Unknown QR codec error'
          : view.errorMsg.toDartString();
      data = '';
    } else {
      error = '';
      data = view.data == nullptr ? '' : view.data.toDartString();
    }
    _freeResult(result);
    if (failed) throw UrCodecException(error);
    return data;
  }

  List<String> _frames(String json) {
    final map = _decodeMap(json);
    final frames = map['frames'];
    if (frames is! List) return const [];
    return frames.whereType<String>().toList(growable: false);
  }

  static Map<String, dynamic> _decodeMap(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const UrCodecException('Malformed codec reply');
    }
    return decoded;
  }

  static int _asInt(Object? value) => (value as num?)?.toInt() ?? 0;

  static Pointer<Utf8> _toNative(String value) => value.toNativeUtf8();
}

/// 一次原生会话句柄。去重与进度都在 Rust 侧，这里只做转发。
class _UrSession implements IUrSession {
  _UrSession(this._bridge, this._handle);

  final UrBridge _bridge;
  Pointer<Void> _handle;

  bool get _closed => _handle == nullptr;

  @override
  UrReceiveProgress receive(String part) {
    if (_closed) {
      throw const UrCodecException('QR session is closed');
    }
    final text = part.toNativeUtf8();
    try {
      final json = _bridge._read(_bridge._receiveBridge(_handle, text));
      final map = UrBridge._decodeMap(json);
      final status = switch (UrBridge._asInt(map['status'])) {
        1 => UrPartStatus.complete,
        2 => UrPartStatus.duplicate,
        _ => UrPartStatus.pending,
      };
      return UrReceiveProgress(
        status: status,
        received: UrBridge._asInt(map['received']),
        total: UrBridge._asInt(map['total']),
      );
    } finally {
      malloc.free(text);
    }
  }

  @override
  UrSessionResult? result() {
    if (_closed) return null;
    final json = _bridge._read(_bridge._sessionResultBridge(_handle));
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return null;
    final type = decoded['type'];
    final cbor = decoded['cbor'];
    if (type is! String || cbor is! String) return null;
    return UrSessionResult(
      type: type,
      cbor: CryptoBridge.hexToBytes(cbor),
    );
  }

  @override
  void dispose() {
    final handle = _handle;
    _handle = nullptr;
    if (handle != nullptr) _bridge._freeSession(handle);
  }
}
