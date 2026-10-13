import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// Empty state shown when the route carries no account (e.g. a direct
/// deep-link to `/account/:id` without [GoRouterState.extra]).
class AccountDetailPlaceholder extends StatelessWidget {
  const AccountDetailPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.neobrutalism)
            NeoCard(
              child: SizedBox(
                width: 88,
                height: 88,
                child: Icon(
                  Icons.qr_code,
                  size: 44,
                  color: c.text.withAlpha(60),
                ),
              ),
            )
          else
            Icon(Icons.qr_code, size: 64, color: c.text.withAlpha(60)),
          SizedBox(height: c.neobrutalism ? 20 : 16),
          Text(
            AppLocalizations.of(context)!.noAccountSelected,
            style: TextStyle(color: c.text.withAlpha(120), fontSize: 16),
          ),
        ],
      ),
    );
  }
}
