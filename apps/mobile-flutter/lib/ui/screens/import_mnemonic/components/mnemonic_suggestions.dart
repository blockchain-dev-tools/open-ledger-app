import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// BIP-39 prefix-suggestion strip shown under the mnemonic input.
///
/// Each chip completes the word currently being typed. Chips are keyed
/// `mnemonic-suggestion-<word>` so tests and gallery screenshots can target
/// them; the widget renders nothing when there are no suggestions.
class MnemonicSuggestions extends StatelessWidget {
  /// Candidate words, already ordered alphabetically by the caller.
  final List<String> suggestions;

  /// Called with the tapped word (the caller appends the trailing space).
  final ValueChanged<String> onTap;

  /// Key applied to the chip for [word].
  static Key keyFor(String word) => ValueKey('mnemonic-suggestion-$word');

  const MnemonicSuggestions({
    super.key,
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final edge = c.neobrutalism ? c.neoEdge : c.borderStrong;

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final word in suggestions)
            OutlinedButton(
              key: keyFor(word),
              onPressed: () => onTap(word),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: edge,
                  width: c.neobrutalism ? Neo.edge : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                word,
                style: TextStyle(
                  color: c.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
