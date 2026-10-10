import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// Displays a BIP-39 mnemonic word list in a numbered or plain grid.
///
/// Shared by [GenerateMnemonicScreen] (3×4, 12 words), [EnigmaMnemonicScreen]
/// (4×6, 24 words), and [BackupSeedScreen] (3×4, 12 words — revealed view).
///
/// Each cell is a rounded container with the word (optionally prefixed by
/// its 1-based index).
///
/// ```dart
/// MnemonicWordGrid(
///   words: 'abandon ability able about ...'.split(' '),
///   columns: 3,
///   numbered: true,
/// )
/// ```
class MnemonicWordGrid extends StatelessWidget {
  /// The list of mnemonic words to display.
  final List<String> words;

  /// Number of grid columns.
  ///
  /// Default: 3 (for 12-word phrases). Use 4 for 24-word Enigma phrases.
  final int columns;

  /// Whether to prefix each word with its 1-based index (e.g. "1. abandon").
  ///
  /// Default: `true`.
  final bool numbered;

  /// Font size for word text.
  ///
  /// Default: 14.
  final double fontSize;

  /// Whether to use a monospace font.
  ///
  /// Default: `false`.
  final bool monospace;

  /// Aspect ratio of each grid cell (width / height).
  ///
  /// Default: 2.6 (good for 3-column grids; use 2.0 for 4-column).
  final double childAspectRatio;

  /// Spacing between grid cells in both axes.
  ///
  /// Default: 10 for cross-axis, 10 for main-axis.
  final double cellSpacing;

  const MnemonicWordGrid({
    super.key,
    required this.words,
    this.columns = 3,
    this.numbered = true,
    this.fontSize = 14.0,
    this.monospace = false,
    this.childAspectRatio = 2.6,
    this.cellSpacing = 10.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: cellSpacing,
        crossAxisSpacing: cellSpacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: words.length,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.center,
          child: Text(
            numbered ? '${index + 1}. ${words[index]}' : words[index],
            style: TextStyle(
              color: c.text,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              fontFamily: monospace ? 'monospace' : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
