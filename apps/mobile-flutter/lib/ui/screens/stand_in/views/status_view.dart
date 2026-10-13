import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../components/action_group.dart';
import '../components/action_row.dart';
import '../stand_in_style.dart';

/// The configured stand-in status view: a "configured" card summarising the
/// active mode plus the grouped Change-PIN / Change-mode / Remove actions.
class StatusView extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  /// Localized label of the currently stored mode (hide / wipe).
  final String modeName;

  final VoidCallback onChangePin;
  final VoidCallback onChangeMode;
  final VoidCallback onRemove;

  const StatusView({
    super.key,
    required this.c,
    required this.l10n,
    required this.modeName,
    required this.onChangePin,
    required this.onChangeMode,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(R.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(R.lg),
                ),
                child: Icon(Icons.shield_outlined, color: c.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.standInConfigured,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.standInCurrentModeLabel}: $modeName',
                      style: TextStyle(
                        color: standInSecondaryText(
                          c,
                          Theme.of(context).brightness,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Actions share one inset card with hairline dividers — the same
        // grouped language as the Settings list, not three floating cards.
        ActionGroup(
          c: c,
          rows: [
            ActionRow(
              key: const ValueKey('standin-action-change-pin'),
              c: c,
              icon: Icons.lock_outline,
              label: l10n.standInChangePinTitle,
              onTap: onChangePin,
            ),
            ActionRow(
              key: const ValueKey('standin-action-change-mode'),
              c: c,
              icon: Icons.tune,
              label: l10n.standInChangeModeTitle,
              value: modeName,
              onTap: onChangeMode,
            ),
            ActionRow(
              key: const ValueKey('standin-action-remove'),
              c: c,
              icon: Icons.delete_outline,
              label: l10n.standInRemoveTitle,
              destructive: true,
              onTap: onRemove,
            ),
          ],
        ),
      ],
    );
  }
}
