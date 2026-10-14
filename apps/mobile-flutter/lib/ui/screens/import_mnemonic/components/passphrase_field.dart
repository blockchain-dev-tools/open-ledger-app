import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// Optional BIP-39 passphrase input with a show/hide toggle.
///
/// In neo (light) the field becomes an outlined [NeoCard] and its label turns
/// black; dark keeps the original hairline-outlined surface card.
class PassphraseField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscurePassphrase;
  final VoidCallback onToggleObscure;

  const PassphraseField({
    super.key,
    required this.controller,
    required this.obscurePassphrase,
    required this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: double.infinity,
      height: 140,
      child: NeoCard(
        padding: const EdgeInsets.all(16),
        // Dark keeps the original hairline-outlined surface card.
        legacyEdge: c.border,
        legacyEdgeWidth: 1.5,
        legacyRadius: R.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.passphraseOptional,
              style: TextStyle(
                color: c.neobrutalism ? c.text : c.text.withAlpha(150),
                fontSize: 13,
                fontWeight: c.neobrutalism ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: TextField(
                key: const Key('passphrase-input'),
                controller: controller,
                obscureText: obscurePassphrase,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Advanced: additional BIP39 passphrase',
                  hintStyle:
                      TextStyle(color: c.text.withAlpha(80), fontSize: 14),
                  suffixIcon: GestureDetector(
                    onTap: onToggleObscure,
                    child: Icon(
                      obscurePassphrase
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 20,
                      color: c.text.withAlpha(140),
                    ),
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
