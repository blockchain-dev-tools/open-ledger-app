import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../stand_in_style.dart';

/// Fallback shown when the screen is reached without a [IWalletService]
/// (e.g. deep-link / gallery without a wired service).
class UnavailableView extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  const UnavailableView({super.key, required this.c, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: c.text.withAlpha(120)),
            const SizedBox(height: 16),
            Text(
              l10n.standInUnavailable,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: standInSecondaryText(c, Theme.of(context).brightness),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
