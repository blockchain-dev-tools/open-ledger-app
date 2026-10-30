import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../biz/qr_sign_flow.dart';
import '../../core/interfaces/ur_codec.dart';
import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';
import 'keystone_review_page.dart';

/// 扫码页：相机收 `eth-sign-request` 帧，收齐后切到审阅页。
///
/// 相机界面固定用深色 chrome（白底取景框看不清），与助记词扫码页一致。
class KeystoneScanPage extends StatefulWidget {
  final IUrCodec codec;
  final String seedHex;

  const KeystoneScanPage({
    super.key,
    required this.codec,
    required this.seedHex,
  });

  @override
  State<KeystoneScanPage> createState() => _KeystoneScanPageState();
}

class _KeystoneScanPageState extends State<KeystoneScanPage> {
  late final QrSignFlow _flow = QrSignFlow(
    codec: widget.codec,
    seedHex: widget.seedHex,
  );

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  /// 已经切到审阅页，避免重复 push。
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _flow.addListener(_onFlowChanged);
    _flow.start();
  }

  @override
  void dispose() {
    _flow.removeListener(_onFlowChanged);
    _controller.dispose();
    _flow.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _flow.submitFrame(raw);
    }
  }

  Future<void> _onFlowChanged() async {
    if (!mounted) return;
    setState(() {});
    if (_flow.phase != QrSignPhase.review || _navigating) return;
    _navigating = true;
    await _controller.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => KeystoneReviewPage(flow: _flow)),
    );
    if (!mounted) return;
    if (_flow.phase == QrSignPhase.scanning) {
      // 审阅页要求重扫：会话已重置，继续用同一台相机。
      _navigating = false;
      await _controller.start();
      return;
    }
    if (_flow.phase == QrSignPhase.signing ||
        _flow.phase == QrSignPhase.signature) {
      // 审阅页用 `pushReplacement` 换成了回显页，栈顶已经不是本页。
      // 这里再 `pop()` 会把回显页弹掉，只剩一台已停机的相机（黑屏）；
      // 收尾交给回显页的「完成」（popUntil 首页）。
      return;
    }
    Navigator.of(context).pop();
  }

  void _close() {
    _flow.cancel();
    Navigator.of(context).pop();
  }

  String _failureText(AppLocalizations l10n) {
    return switch (_flow.failure) {
      QrSignFailure.timeout => l10n.keystoneErrorTimeout,
      QrSignFailure.unexpectedQr => l10n.keystoneErrorUnexpectedQr,
      QrSignFailure.invalidRequest => l10n.keystoneErrorInvalidRequest,
      QrSignFailure.codecUnavailable => l10n.keystoneErrorCodecUnavailable,
      QrSignFailure.signingFailed => l10n.keystoneErrorSigning,
      null => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 相机页固定深色，与主题无关。
    final c = ColorTokens.dark;
    final progress = _flow.progress;
    final failed = _flow.phase == QrSignPhase.failed;

    return Scaffold(
      key: const Key('keystone-scan-page'),
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              key: const Key('keystone-scan-view'),
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                final denied =
                    error.errorCode == MobileScannerErrorCode.permissionDenied;
                return ColoredBox(
                  color: c.bg,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        denied
                            ? l10n.qrScanPermissionDenied
                            : l10n.qrScanCameraError,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.text, fontSize: 14),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('keystone-scan-close'),
                        onPressed: _close,
                        icon: Icon(Icons.close, color: c.text),
                      ),
                      Expanded(
                        child: Text(
                          l10n.keystoneScanTitle,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (failed)
                  _FailureCard(
                    message: _failureText(l10n),
                    detail: _flow.errorDetail,
                    retryLabel: l10n.keystoneRetry,
                    c: c,
                    onRetry: _flow.start,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(
                          progress == null || progress.received == 0
                              ? l10n.keystoneScanHint
                              : l10n.keystoneScanProgress(
                                  progress.received,
                                  progress.total,
                                ),
                          key: const Key('keystone-scan-progress'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.text.withAlpha(200),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  final String message;
  final String? detail;
  final String retryLabel;
  final ColorTokens c;
  final VoidCallback onRetry;

  const _FailureCard({
    required this.message,
    required this.detail,
    required this.retryLabel,
    required this.c,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('keystone-scan-error'),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text, fontSize: 13),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.text.withAlpha(130), fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('keystone-scan-retry'),
            onPressed: onRetry,
            // 相机页永远是深色 chrome，按钮颜色显式取深色 token，
            // 不受日间主题的 Material 默认值影响。
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.onPrimary,
            ),
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}
