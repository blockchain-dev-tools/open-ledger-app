import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// The 12-word mnemonic input box, with a clear button in the corner.
///
/// Uses a fixed height instead of `Expanded`: inside the page's
/// `SingleChildScrollView` the height is unbounded, so `Expanded` would throw.
/// The border colour reflects the current validation state.
class MnemonicInputField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasChecked;
  final bool isValid;

  const MnemonicInputField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasChecked,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return SizedBox(
      height: 200,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: _borderColor(c), width: 1.5),
        ),
        child: Stack(
          children: [
            TextField(
              key: const Key('mnemonic-input'),
              controller: controller,
              onChanged: onChanged,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                height: 1.6,
                letterSpacing: 0.4,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'word1 word2 word3 ...',
                hintStyle: TextStyle(color: c.text.withAlpha(80), fontSize: 15),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              autocorrect: false,
              enableSuggestions: false,
            ),

            // Clear button (top-right corner)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: 20,
                  color: c.text.withAlpha(100),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the border color for the input field based on validation state.
  Color _borderColor(ColorTokens c) {
    if (!hasChecked) return c.border;
    if (isValid) return c.primary;
    return c.error;
  }
}
