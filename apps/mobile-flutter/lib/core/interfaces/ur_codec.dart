import 'dart:typed_data';

import '../models/ur_qr.dart';

/// 一次扫码接收会话。实现负责去重、进度与超时判定。
abstract class IUrSession {
  /// 收一帧；重复帧返回 [UrPartStatus.duplicate] 而不是抛错。
  UrReceiveProgress receive(String part);

  /// 完成后的结果；未完成是 `null`。
  UrSessionResult? result();

  void dispose();
}

/// BC-UR 编解码 + ETH QR 签名的抽象。
///
/// UI 与流程只依赖本接口；真实现是 `UrBridge`（FFI），单测用假实现。
abstract class IUrCodec {
  /// 原生库是否导出了 UR 符号。`false` 时入口不应出现。
  bool get isAvailable;

  IUrSession newSession();

  EthSignRequestView parseSignRequest(Uint8List cbor);

  /// 地址不匹配、typed data、哈希失败都会抛 [UrCodecException]。
  EthSignResult signRequest(Uint8List cbor, String seedHex);

  /// `fragmentLength == 0` 时返回单帧。
  List<String> encodeSignature({
    required String requestIdHex,
    required Uint8List signature,
    String? origin,
    int fragmentLength = 0,
  });

  /// 一张账户码带 [count] 个连续账户（主机按页取地址，MetaMask 一页 5 个）。
  ///
  /// [accountLevel] 为 true 时输出 Keystone 风格的**账户级单公钥**
  /// （`path` 指向账户节点，主机自行派生），供 OKX 之类的主机使用。
  CryptoAccountExport encodeAccount({
    required String seedHex,
    required String path,
    int count = 1,
    bool accountLevel = false,
    int fragmentLength = 0,
  });
}
