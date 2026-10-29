import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../biz/qr_sign_flow.dart';
import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';

/// 回显页：循环播放 `eth-signature` 帧，让主机扫码取回签名。
class KeystoneSignaturePage extends StatefulWidget {
  final QrSignFlow flow;

  const KeystoneSignaturePage({super.key, required this.flow});

  @override
  State<KeystoneSignaturePage> createState() => _KeystoneSignaturePageState();
}

class _KeystoneSignaturePageState extends State<KeystoneSignaturePage> {
  int _frameIndex = 0;
  Timer? _loop;

  @override
  void initState() {
    super.initState();
    final frames = widget.flow.signatureFrames;
    if (frames.length > 1) {
      _loop = Timer.periodic(const Duration(milliseconds: 180), (_) {
        if (!mounted) return;
        setState(() => _frameIndex = (_frameIndex + 1) % frames.length);
      });
    }
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  void _done() {
    widget.flow.cancel();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final frames = widget.flow.signatureFrames;
    final size = MediaQuery.of(context).size.shortestSide * 0.72;

    return Scaffold(
      key: const Key('keystone-signature-page'),
      backgroundColor: c.groupedBg,
      appBar: AppBar(
        backgroundColor: c.groupedBg,
        foregroundColor: c.text,
        automaticallyImplyLeading: false,
        title: Text(l10n.keystoneSignatureTitle),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                children: [
                  Text(
                    l10n.keystoneSignatureHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text.withAlpha(170), fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: frames.isEmpty
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: QrImageView(
                              key: const Key('keystone-signature-qr'),
                              data: frames[_frameIndex],
                              version: QrVersions.auto,
                              size: size - 28,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            ),
                          ),
                  ),
                  if (frames.length > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_frameIndex + 1} / ${frames.length}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text.withAlpha(120),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: FilledButton(
                key: const Key('keystone-signature-done'),
                onPressed: _done,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(l10n.keystoneDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
