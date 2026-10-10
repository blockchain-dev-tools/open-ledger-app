import 'package:flutter/material.dart';

import '../../../core/interfaces/backup_verifier.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';

/// Renders the outcome of one backup-verification attempt (ADR-011 §5).
///
/// The three states are deliberately distinct in colour and wording:
/// [VerifyResult.match] confirms the backup, [VerifyResult.mismatch] asks the
/// user to check for typos, and [VerifyResult.unavailable] must never read as
/// "wrong" — it means the check could not run (locked session, or no Ethereum
/// baseline account), so the user's memory is not blamed for it.
class VerifyResultCard extends StatelessWidget {
  const VerifyResultCard({super.key, required this.result});

  final VerifyResult result;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    final (Color color, IconData icon, String message) = switch (result) {
      VerifyResult.match => (
          c.primary,
          Icons.check_circle_outline,
          l10n.verifyResultMatch,
        ),
      VerifyResult.mismatch => (
          c.error,
          Icons.error_outline,
          l10n.verifyResultMismatch,
        ),
      VerifyResult.unavailable => (
          c.text.withAlpha(160),
          Icons.help_outline,
          l10n.verifyResultUnavailable,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
