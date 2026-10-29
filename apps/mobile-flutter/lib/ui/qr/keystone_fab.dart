import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';

/// Keystone 二维码入口的悬浮按钮，固定在 BLE 按钮上方。
///
/// 与 BLE 悬浮按钮的分工（T-026 IA 决策）：BLE 独占「在线」状态灯，这里只做
/// 静态图标 + 会话中的一个小进度点，避免两个按钮互相竞争状态语义。
class KeystoneFab extends StatelessWidget {
  /// `null` 表示暂时不可用（BLE 有待确认请求或当前有 QR 会话在跑）。
  final VoidCallback? onTap;

  /// 会话进行中：右下角显示一个呼吸的进度点。
  final bool busy;

  const KeystoneFab({super.key, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final disabled = onTap == null;

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Material(
            color: disabled ? c.text.withAlpha(22) : c.surface,
            shape: CircleBorder(
              side: BorderSide(color: c.text.withAlpha(disabled ? 30 : 60)),
            ),
            elevation: disabled ? 0 : 2,
            child: InkWell(
              key: const Key('keystone-fab'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Icon(
                    Icons.qr_code_2,
                    size: 26,
                    color: disabled ? c.text.withAlpha(70) : c.text,
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
