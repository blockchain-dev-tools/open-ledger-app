import 'dart:async';

import 'package:flutter/material.dart';

import '../../biz/qr_sign_flow.dart';
import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';
import '../widgets/common/adaptive_action_button.dart';
import '../widgets/common/grid_background.dart';
import '../widgets/common/neo_app_bar.dart';
import '../widgets/common/qr_display_card.dart';

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
      appBar: neoAppBar(
        c: c,
        darkBackground: c.groupedBg,
        automaticallyImplyLeading: false,
        title: Text(l10n.keystoneSignatureTitle),
      ),
      body: GridBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  children: [
                    Text(
                      l10n.keystoneSignatureHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.mutedText(170), fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    if (frames.isEmpty)
                      const SizedBox.shrink()
                    else
                      // 白底二维码卡片；日间模式带黑描边，深色保留细边。
                      QrDisplayCard(
                        key: const Key('keystone-signature-qr'),
                        data: frames[_frameIndex],
                        size: size - 24,
                      ),
                    if (frames.length > 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_frameIndex + 1} / ${frames.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.mutedText(120), fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: AdaptiveActionButton(
                  key: const Key('keystone-signature-done'),
                  label: l10n.keystoneDone,
                  onTap: _done,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
