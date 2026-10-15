import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import 'neo_button.dart';
import 'primary_button.dart';

/// The screen's primary/secondary action, in whichever chrome the theme speaks.
///
/// [NeoButton] has no disabled or loading state of its own — the neo block is
/// always live — so an action that can be *disabled* keeps the flat
/// [PrimaryButton] chrome in both themes and only becomes a neo block while it
/// is actually tappable.
///
/// ```dart
/// AdaptiveActionButton(label: l10n.approve, onTap: _onApprove)
///
/// // The reject action is quiet in neo and an error-outlined flat button in
/// // dark; both tones describe the same "not the happy path" intent.
/// AdaptiveActionButton(
///   label: l10n.reject,
///   quiet: true,
///   legacyOutlineColor: c.error,
///   onTap: _onReject,
/// )
/// ```
class AdaptiveActionButton extends StatelessWidget {
  /// Button label.
  final String label;

  /// Called on tap. `null` — or [loading] — renders the flat disabled button.
  final VoidCallback? onTap;

  /// Neo tone: a quiet block instead of the brand-lime one.
  final bool quiet;

  /// Legacy tone: the flat outline button.
  final bool legacyOutline;

  /// Legacy outline colour, used for both the border and the label to match
  /// [PrimaryButton.outlineColor]. Passing it implies [legacyOutline].
  final Color? legacyOutlineColor;

  /// Stretches the neo block to its parent's width. [PrimaryButton] is always
  /// full width, so leave this on unless the caller sizes the button itself.
  final bool expanded;

  /// Shows a spinner and disables the button. Forces the legacy chrome.
  final bool loading;

  /// Optional leading glyph (neo chrome only, like [NeoButton]).
  final IconData? icon;

  /// Optional trailing glyph (neo chrome only, like [NeoButton]).
  final IconData? trailingIcon;

  /// Legacy button height; neo blocks size themselves.
  final double height;

  const AdaptiveActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.quiet = false,
    this.legacyOutline = false,
    this.legacyOutlineColor,
    this.expanded = true,
    this.loading = false,
    this.icon,
    this.trailingIcon,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    if (c.neobrutalism && onTap != null && !loading) {
      return NeoButton(
        label: label,
        expanded: expanded,
        quiet: quiet,
        icon: icon,
        trailingIcon: trailingIcon,
        onTap: onTap!,
      );
    }

    return PrimaryButton(
      label: label,
      onTap: loading ? null : onTap,
      height: height,
      loading: loading,
      outline: legacyOutline || legacyOutlineColor != null,
      outlineColor: legacyOutlineColor,
    );
  }
}
