import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../theme/color_tokens.dart';

/// 入口抽屉里的两个动作。
enum KeystoneEntry { exportAccount, scanAndSign }

/// Keystone 入口抽屉。
///
/// 只做菜单：点任一动作就返回，由调用方先关闭再推全屏页——house rule 是
/// 不在一个 sheet 上再叠一层 sheet。返回 `null` 表示用户取消。
Future<KeystoneEntry?> showKeystoneEntrySheet(BuildContext context) {
  return showModalBottomSheet<KeystoneEntry>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final c = isDark ? ColorTokens.dark : ColorTokens.light;
      final l10n = AppLocalizations.of(context)!;
      return SafeArea(
        key: const Key('keystone-entry-sheet'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.keystoneTitle,
                style: TextStyle(
                  color: c.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              key: const Key('keystone-entry-export'),
              leading: Icon(Icons.qr_code_2, color: c.text),
              title: Text(
                l10n.keystoneEntryExport,
                style: TextStyle(color: c.text),
              ),
              subtitle: Text(
                l10n.keystoneExportHint,
                style: TextStyle(color: c.text.withAlpha(150), fontSize: 12),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(KeystoneEntry.exportAccount),
            ),
            ListTile(
              key: const Key('keystone-entry-scan'),
              leading: Icon(Icons.qr_code_scanner, color: c.text),
              title: Text(
                l10n.keystoneEntryScan,
                style: TextStyle(color: c.text),
              ),
              subtitle: Text(
                l10n.keystoneScanHint,
                style: TextStyle(color: c.text.withAlpha(150), fontSize: 12),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(KeystoneEntry.scanAndSign),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}
