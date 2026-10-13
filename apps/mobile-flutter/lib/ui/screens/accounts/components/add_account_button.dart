import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_button.dart';

/// The "Add Account" action at the foot of an expanded chain section.
///
/// Light mode renders the neo button; dark keeps the original bare label row
/// (no fill, no outline). The tap is delegated to [onTap].
class AddAccountButton extends StatelessWidget {
  final String chain;
  final VoidCallback onTap;

  const AddAccountButton({super.key, required this.chain, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    if (c.neobrutalism) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: NeoButton(
          key: ValueKey('add-account-$chain'),
          label: AppLocalizations.of(context)!.addAccount,
          icon: Icons.add,
          expanded: true,
          onTap: onTap,
        ),
      );
    }
    // Dark keeps the original bare label row: no fill, no outline.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: GestureDetector(
        key: ValueKey('add-account-$chain'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: c.accent),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.addAccount,
                style: TextStyle(
                  color: c.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
