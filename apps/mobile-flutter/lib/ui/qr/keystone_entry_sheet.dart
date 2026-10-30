import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';
import '../widgets/common/neo_card.dart';
import '../widgets/common/neo_rule.dart';
import '../widgets/common/neo_sheet.dart';

/// 入口抽屉里的两个动作。
enum KeystoneEntry { exportAccount, scanAndSign }

/// Keystone 入口抽屉。
///
/// 只做菜单：点任一动作就返回，由调用方先关闭再推全屏页——house rule 是
/// 不在一个 sheet 上再叠一层 sheet。返回 `null` 表示用户取消。
///
/// 日间模式跟其余 neo 面板一致：黑描边 + 紧圆角 + 标题下的粗分隔线，动作前
/// 的图标装进 lime 方块；深色模式保持原来的软圆角抽屉。
Future<KeystoneEntry?> showKeystoneEntrySheet(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final c = isDark ? ColorTokens.dark : ColorTokens.light;
  final neo = c.neobrutalism;

  return showModalBottomSheet<KeystoneEntry>(
    context: context,
    backgroundColor: c.surface,
    shape: neoSheetShape(c),
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      return SafeArea(
        key: const Key('keystone-entry-sheet'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            neoSheetHandle(c, width: 40),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Text(
                l10n.keystoneTitle,
                style: TextStyle(
                  color: c.text,
                  fontSize: 17,
                  fontWeight: neo ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
            if (neo) neoRule(c, heavy: true),
            _EntryRow(
              key: const Key('keystone-entry-export'),
              icon: Icons.qr_code_2,
              title: l10n.keystoneEntryExport,
              subtitle: l10n.keystoneExportHint,
              c: c,
              onTap: () =>
                  Navigator.of(sheetContext).pop(KeystoneEntry.exportAccount),
            ),
            if (neo) neoRule(c),
            _EntryRow(
              key: const Key('keystone-entry-scan'),
              icon: Icons.qr_code_scanner,
              title: l10n.keystoneEntryScan,
              subtitle: l10n.keystoneScanHint,
              c: c,
              onTap: () =>
                  Navigator.of(sheetContext).pop(KeystoneEntry.scanAndSign),
            ),
            SizedBox(height: neo ? 10 : 12),
          ],
        ),
      );
    },
  );
}

class _EntryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorTokens c;
  final VoidCallback onTap;

  const _EntryRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      icon,
      size: 22,
      color: c.neobrutalism ? c.brandInk : c.text,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            if (c.neobrutalism)
              NeoCard(
                lifted: false,
                fill: c.actionFill,
                padding: const EdgeInsets.all(7),
                child: glyph,
              )
            else
              glyph,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: c.mutedText(150),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (c.neobrutalism)
              Icon(Icons.chevron_right, size: 20, color: c.text),
          ],
        ),
      ),
    );
  }
}
