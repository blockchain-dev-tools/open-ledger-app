import 'package:flutter/material.dart';

import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';

/// Optional BIP-39 passphrase input with a show/hide toggle.
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

    return Container(
      width: double.infinity,
      height: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: c.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.passphraseOptional,
            style: TextStyle(
              color: c.text.withAlpha(150),
              fontSize: 13,
              fontWeight: FontWeight.w500,
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
                hintStyle: TextStyle(color: c.text.withAlpha(80), fontSize: 14),
                suffixIcon: GestureDetector(
                  onTap: onToggleObscure,
                  child: Icon(
                    obscurePassphrase ? Icons.visibility_off : Icons.visibility,
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
    );
  }
}
