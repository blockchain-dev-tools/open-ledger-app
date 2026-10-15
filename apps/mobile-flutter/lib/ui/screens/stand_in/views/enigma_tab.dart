import 'package:flutter/material.dart';

import '../../../../data/bip39_wordlist.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_button.dart';
import '../../../widgets/common/primary_button.dart';
import '../../../widgets/mnemonic/mnemonic_language_picker.dart';
import '../../../widgets/mnemonic/mnemonic_word_grid.dart';
import '../../../widgets/mnemonic/warning_banner.dart';
import '../components/check_row.dart';
import '../stand_in_style.dart';

/// Enigma tab — riddle + secret key derive a deterministic 24-word phrase.
///
/// Mirrors the main wallet's Enigma screen (multiline riddle, wordlist
/// picker, masked secret with a reveal toggle, tip copy). Before generation
/// the pinned CTA derives the phrase; afterwards the grid + "I've written it
/// down" gate the continue action, exactly like the generate tab.
class EnigmaTab extends StatelessWidget {
  final ColorTokens c;
  final AppLocalizations l10n;

  final TextEditingController riddleController;
  final TextEditingController secretController;

  /// Words produced by the last successful derivation, empty until then.
  final List<String> words;
  final bool wordsConfirmed;
  final bool generating;

  /// Error surfaced from the last derivation, if any.
  final String? error;

  final bool obscureSecret;
  final Bip39WordlistLanguage language;

  /// Clears a previous failure as soon as the user edits the inputs.
  final VoidCallback onFieldChanged;
  final VoidCallback onObscureToggled;
  final ValueChanged<Bip39WordlistLanguage> onLanguageChanged;
  final VoidCallback onToggleConfirmed;
  final VoidCallback onGenerate;
  final VoidCallback onContinue;

  const EnigmaTab({
    super.key,
    required this.c,
    required this.l10n,
    required this.riddleController,
    required this.secretController,
    required this.words,
    required this.wordsConfirmed,
    required this.generating,
    required this.error,
    required this.obscureSecret,
    required this.language,
    required this.onFieldChanged,
    required this.onObscureToggled,
    required this.onLanguageChanged,
    required this.onToggleConfirmed,
    required this.onGenerate,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = standInSecondaryText(c, Theme.of(context).brightness);
    final generated = words.isNotEmpty;
    final cta = _buildCta(l10n, generated: generated);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.standInCreateTitle,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.enigmaDescription,
                  style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 18),
                if (generated) ...[
                  WarningBanner(message: l10n.generateMnemonicWarning),
                  const SizedBox(height: 18),
                  MnemonicWordGrid(
                    words: words,
                    columns: 4,
                    fontSize: 12,
                    childAspectRatio: 2.0,
                    cellSpacing: 6.0,
                    neo: c.neobrutalism,
                  ),
                  const SizedBox(height: 20),
                  CheckRow(
                    key: const ValueKey('standin-enigma-written-down'),
                    c: c,
                    label: l10n.iveWrittenItDown,
                    checked: wordsConfirmed,
                    onTap: onToggleConfirmed,
                  ),
                ] else ...[
                  _fieldLabel(c, l10n.yourRiddle),
                  const SizedBox(height: 8),
                  _enigmaField(
                    c: c,
                    controller: riddleController,
                    fieldKey: const Key('standin-enigma-riddle'),
                    hint: l10n.enterMemorablePhrase,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel(c, l10n.mnemonicLanguage),
                  const SizedBox(height: 8),
                  MnemonicLanguageTrigger(
                    key: const ValueKey('standin-enigma-language'),
                    language: language,
                    onChanged: onLanguageChanged,
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel(c, l10n.secretKey),
                  const SizedBox(height: 8),
                  _enigmaField(
                    c: c,
                    controller: secretController,
                    fieldKey: const Key('standin-enigma-secret'),
                    hint: l10n.enterSecretKey,
                    obscure: obscureSecret,
                    suffix: IconButton(
                      key: const ValueKey('standin-enigma-secret-toggle'),
                      icon: Icon(
                        obscureSecret ? Icons.visibility_off : Icons.visibility,
                        color: c.text.withAlpha(150),
                        size: 20,
                      ),
                      onPressed: onObscureToggled,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tipLongUnique,
                    style: TextStyle(
                      color: c.text.withAlpha(100),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      error!,
                      style: TextStyle(color: c.error, fontSize: 13),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: cta,
        ),
      ],
    );
  }

  /// The pinned footer action: derive before generation, continue after. Neo
  /// renders the neo button only when the action is enabled; the gated cases
  /// keep the original flat button (which owns the disabled + loading chrome).
  Widget _buildCta(AppLocalizations l10n, {required bool generated}) {
    if (generated) {
      if (c.neobrutalism && wordsConfirmed) {
        return NeoButton(
          key: const Key('standin-enigma-continue'),
          label: l10n.continueButton,
          expanded: true,
          onTap: onContinue,
        );
      }
      return PrimaryButton(
        key: const Key('standin-enigma-continue'),
        label: l10n.continueButton,
        onTap: wordsConfirmed ? onContinue : null,
      );
    }
    final enabled =
        riddleController.text.trim().isNotEmpty &&
        secretController.text.trim().isNotEmpty &&
        !generating;
    if (c.neobrutalism && enabled) {
      return NeoButton(
        key: const Key('standin-enigma-generate'),
        label: l10n.generateWallet,
        expanded: true,
        onTap: onGenerate,
      );
    }
    return PrimaryButton(
      key: const Key('standin-enigma-generate'),
      label: l10n.generateWallet,
      loading: generating,
      onTap: enabled ? onGenerate : null,
    );
  }

  /// Field label used inside the Enigma tab (matches the main Enigma screen).
  Widget _fieldLabel(ColorTokens c, String text) => Text(
    text,
    style: TextStyle(
      color: c.text.withAlpha(200),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );

  /// Surface-filled text field shared by the Enigma tab's riddle + secret.
  Widget _enigmaField({
    required ColorTokens c,
    required TextEditingController controller,
    required Key fieldKey,
    required String hint,
    int maxLines = 1,
    bool obscure = false,
    Widget? suffix,
  }) {
    final neo = c.neobrutalism;
    final radius = BorderRadius.circular(neo ? Neo.radius : R.lg);
    return TextField(
      key: fieldKey,
      controller: controller,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      style: TextStyle(color: c.text, fontSize: 15),
      // Rebuild so the generate CTA tracks the field contents; also clears a
      // previous failure as soon as the user edits the inputs.
      onChanged: (_) => onFieldChanged(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.text.withAlpha(100), fontSize: 14),
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.all(16),
        suffixIcon: suffix,
        // Neo draws a hard brand-ink outline (deep green on focus); dark keeps
        // the original hairline border and lime focus ring.
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: neo ? c.neoEdge : c.border,
            width: neo ? Neo.edge : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: neo ? c.neoEdge : c.border,
            width: neo ? Neo.edge : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: c.accent,
            width: neo ? Neo.edge : 1.5,
          ),
        ),
      ),
      // Only the masked secret key disables suggestions/autocorrect — that is
      // what legitimately triggers the IME's secure mode on some ROMs. The
      // riddle stays a plain text field so the normal keyboard is shown
      // (matching the main Enigma screen).
      autocorrect: !obscure,
      enableSuggestions: !obscure,
    );
  }
}
