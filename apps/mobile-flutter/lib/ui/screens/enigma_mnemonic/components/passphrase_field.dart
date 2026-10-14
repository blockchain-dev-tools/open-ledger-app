import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';

/// The optional BIP-39 passphrase block: label, explanation and the obscured
/// input field with its show/hide toggle.
///
/// Stateless — the [controller], the reveal state ([obscure]) and the reveal
/// toggle ([onToggleObscure]) are all owned by the parent screen, so the field
/// behaviour is unchanged.
class PassphraseField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;

  const PassphraseField({
    super.key,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLocalizations.of(context)!.passphraseOptional,
          style: TextStyle(
            color: c.neobrutalism ? c.text : c.text.withAlpha(150),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context)!.bip39PassphraseExplanation,
          style: TextStyle(
            color: c.text.withAlpha(100),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        NeoCard(
          clip: true,
          // Dark restores the original hairline field.
          legacyEdge: c.border,
          legacyRadius: R.lg,
          child: TextField(
            key: const Key('passphrase-input'),
            controller: controller,
            obscureText: obscure,
            style: TextStyle(color: c.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Enter passphrase (optional)',
              hintStyle: TextStyle(color: c.text.withAlpha(80)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: c.text.withAlpha(150),
                ),
                onPressed: onToggleObscure,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
