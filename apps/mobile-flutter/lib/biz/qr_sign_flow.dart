import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/interfaces/ur_codec.dart';
import '../core/models/ur_qr.dart';

enum QrSignPhase {
  /// 未开始或已收尾。
  idle,

  /// 正在扫主机屏幕上的请求帧。
  scanning,

  /// 帧已收齐，等待用户批准或拒绝。
  review,

  /// 正在派生密钥并签名（同步且很短）。
  signing,

  /// 签名完成，正在循环回显 `eth-signature`。
  signature,

  /// 失败，需要用户重试。
  failed,
}

enum QrSignFailure {
  /// 60 秒内没扫齐。
  timeout,

  /// 扫到的 UR 类型不是 `eth-sign-request`。
  unexpectedQr,

  /// dCBOR 不合法、字段缺失、typed data 等。
  invalidRequest,

  /// 原生库没有导出 UR 符号。
  codecUnavailable,

  /// 派生/签名失败（含地址不匹配）。
  signingFailed,
}

/// 扫码签名的一次性状态机。
///
/// 只依赖 [IUrCodec]，不碰相机与页面；相机把每帧原文交给 [submitFrame]，
/// 页面按 [phase] 切换。会话超时、去重与清理都在这里收口。
class QrSignFlow extends ChangeNotifier {
  QrSignFlow({
    required this.codec,
    required this.seedHex,
    this.timeout = const Duration(seconds: 60),
  });

  final IUrCodec codec;
  final String seedHex;
  final Duration timeout;

  QrSignPhase _phase = QrSignPhase.idle;
  QrSignPhase get phase => _phase;

  UrReceiveProgress? _progress;
  UrReceiveProgress? get progress => _progress;

  EthSignRequestView? _request;
  EthSignRequestView? get request => _request;

  Uint8List? _requestCbor;
  Uint8List? get requestCbor => _requestCbor;

  List<String> _signatureFrames = const [];
  List<String> get signatureFrames => _signatureFrames;

  QrSignFailure? _failure;
  QrSignFailure? get failure => _failure;

  String? _errorDetail;
  String? get errorDetail => _errorDetail;

  IUrSession? _session;
  Timer? _timer;

  /// 开（或重开）一次扫码会话。
  void start() {
    _teardownSession();
    if (!codec.isAvailable) {
      _fail(QrSignFailure.codecUnavailable, null);
      return;
    }
    try {
      _session = codec.newSession();
    } on UrCodecException catch (error) {
      _fail(QrSignFailure.codecUnavailable, error.message);
      return;
    }
    _progress = null;
    _request = null;
    _requestCbor = null;
    _signatureFrames = const [];
    _failure = null;
    _errorDetail = null;
    _phase = QrSignPhase.scanning;
    _timer = Timer(timeout, () {
      _fail(QrSignFailure.timeout, null);
    });
    notifyListeners();
  }

  /// 相机回调。非 `ur:` 内容、非法帧、其他会话的帧都静默忽略。
  void submitFrame(String raw) {
    if (_phase != QrSignPhase.scanning) return;
    final session = _session;
    if (session == null) return;
    final frame = raw.trim();
    if (!frame.toLowerCase().startsWith('ur:')) return;

    UrReceiveProgress progress;
    try {
      progress = session.receive(frame);
    } on UrCodecException {
      // 画面里可能还有别的二维码；收不下就先当作噪声。
      return;
    }
    _progress = progress;
    if (progress.status != UrPartStatus.complete) {
      notifyListeners();
      return;
    }

    final result = session.result();
    if (result == null) {
      _fail(QrSignFailure.invalidRequest, 'Session completed without a payload');
      return;
    }
    if (result.type != 'eth-sign-request') {
      _fail(QrSignFailure.unexpectedQr, result.type);
      return;
    }
    try {
      _request = codec.parseSignRequest(result.cbor);
      _requestCbor = result.cbor;
    } on UrCodecException catch (error) {
      _fail(QrSignFailure.invalidRequest, error.message);
      return;
    }
    _timer?.cancel();
    _timer = null;
    _phase = QrSignPhase.review;
    notifyListeners();
  }

  /// 用户批准：签名并生成回显帧。
  void approve() {
    if (_phase != QrSignPhase.review) return;
    final cbor = _requestCbor;
    final request = _request;
    if (cbor == null || request == null) return;
    _phase = QrSignPhase.signing;
    notifyListeners();

    try {
      final signed = codec.signRequest(cbor, seedHex);
      if (!signed.addressMatches) {
        _fail(QrSignFailure.signingFailed, 'Address mismatch');
        return;
      }
      final frames = codec.encodeSignature(
        requestIdHex: signed.requestIdHex.isEmpty
            ? (request.requestIdHex ?? '')
            : signed.requestIdHex,
        signature: signed.signature,
        origin: request.origin,
      );
      if (frames.isEmpty) {
        _fail(QrSignFailure.signingFailed, 'Empty signature frames');
        return;
      }
      _signatureFrames = frames;
      _phase = QrSignPhase.signature;
      notifyListeners();
    } on UrCodecException catch (error) {
      _fail(QrSignFailure.signingFailed, error.message);
    }
  }

  /// 用户拒绝：丢弃会话，回到空闲。
  void reject() {
    _teardownSession();
    _phase = QrSignPhase.idle;
    _request = null;
    _requestCbor = null;
    _progress = null;
    _signatureFrames = const [];
    notifyListeners();
  }

  /// 取消（返回、关闭页面）。
  void cancel() => reject();

  @override
  void dispose() {
    _teardownSession();
    super.dispose();
  }

  void _fail(QrSignFailure reason, String? detail) {
    _teardownSession();
    _failure = reason;
    _errorDetail = detail;
    _phase = QrSignPhase.failed;
    notifyListeners();
  }

  void _teardownSession() {
    _timer?.cancel();
    _timer = null;
    _session?.dispose();
    _session = null;
  }
}
