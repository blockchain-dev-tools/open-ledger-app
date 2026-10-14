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

    // Light mode paints the verdict as a flat, opaque neo block: the `match`
    // state is a brand note, so it fills with the lime (which forces black ink
    // and the deep-green glyph — the translucent lime tint would wash out);
    // `mismatch` / `unavailable` keep their own colour, with the tint flattened
    // against the surface so the page grid cannot show through. Dark keeps the
    // original translucent tint.
    final neo = c.neobrutalism;
    final Color fill;
    final Color ink;
    final Color glyph;
    if (neo) {
      final brand = result == VerifyResult.match;
      final unavailable = result == VerifyResult.unavailable;
      fill = brand
          ? c.actionFill
          : Color.alphaBlend(color.withAlpha(18), c.surface);
      ink = brand ? c.brandInk : (unavailable ? c.text : color);
      glyph = brand ? c.accent : (unavailable ? c.text : color);
    } else {
      fill = color.withAlpha(18);
      ink = color;
      glyph = color;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(neo ? Neo.radius : R.lg),
        border: Border.all(
          color: neo ? c.neoEdge : color.withAlpha(70),
          width: neo ? Neo.edge : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: glyph, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: ink, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
