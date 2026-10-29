import 'dart:typed_data';

/// Keystone QR 通道（BC-UR）的纯数据模型。
///
/// 字段与 Rust 侧 `open-ledger-ur` 的 JSON 输出一一对应；这里不引入 FFI。

/// 一帧的接收结果。
enum UrPartStatus {
  /// 已收下，还缺帧。
  pending,

  /// 本帧此前已收到过（不算进度）。
  duplicate,

  /// 会话完成。
  complete,
}

class UrReceiveProgress {
  final UrPartStatus status;

  /// 已收到的**不重复**帧数。
  final int received;

  /// 主机声明的总帧数（fountain 编码可能提前完成，仅用于展示）。
  final int total;

  const UrReceiveProgress({
    required this.status,
    required this.received,
    required this.total,
  });
}

/// 完成的 UR 会话结果。
class UrSessionResult {
  /// `eth-sign-request` / `crypto-account` / …
  final String type;
  final Uint8List cbor;

  const UrSessionResult({required this.type, required this.cbor});
}

/// 待审阅的 `eth-sign-request`。
class EthSignRequestView {
  final String? requestIdHex;
  final int dataType;
  final int? chainId;
  final String path;
  final String? address;
  final String? origin;
  final String signDataHex;
  final String signingHashHex;

  const EthSignRequestView({
    required this.requestIdHex,
    required this.dataType,
    required this.chainId,
    required this.path,
    required this.address,
    required this.origin,
    required this.signDataHex,
    required this.signingHashHex,
  });

  /// 待签数据的字节数，审阅页用来提示「不是一串普通文本」。
  int get signDataBytes => signDataHex.length ~/ 2;
}

/// 签名结果（本机派生 + 65 字节 `r || s || v`）。
class EthSignResult {
  final String requestIdHex;
  final Uint8List signature;
  final String address;
  final bool addressMatches;

  const EthSignResult({
    required this.requestIdHex,
    required this.signature,
    required this.address,
    required this.addressMatches,
  });
}

/// `crypto-account` 导出结果：待循环播放的帧 + 展示用地址。
class CryptoAccountExport {
  final List<String> frames;

  /// 这一页的第一个地址（= 用户选中的账户）。
  final String address;

  /// 这一页的全部地址，顺序与派生索引一致。
  final List<String> addresses;

  final String path;

  const CryptoAccountExport({
    required this.frames,
    required this.address,
    required this.addresses,
    required this.path,
  });
}

/// FFI / 编解码失败。UI 直接展示 [message]，不需要区分底层错误码。
class UrCodecException implements Exception {
  final String message;

  const UrCodecException(this.message);

  @override
  String toString() => message;
}
