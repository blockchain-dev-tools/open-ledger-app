import 'package:flutter/material.dart';

/// Design tokens ported from `packages/theme/src/index.ts` in open-ledger-mono.
///
/// Usage:
/// ```dart
/// Container(color: ColorTokens.dark.bg)
/// Text('Hello', style: TextStyle(color: ColorTokens.dark.text))
/// ```
class ColorTokens {
  final Color primary;
  final Color bg;

  /// Tinted background for inset grouped lists (e.g. Settings): pure black
  /// in dark mode, iOS-style `#F2F2F7` in light. Cards ([surface]) sit on
  /// top of it without needing their own border.
  final Color groupedBg;
  final Color surface;
  final Color text;
  final Color error;
  final Color onPrimary;
  final Color onBg;
  final Color border;

  /// Higher-contrast border for unselected grouped cards (e.g. the chain
  /// sections in Accounts). Light mode uses pure black so card edges read
  /// crisply against white; dark mode keeps the neutral [border].
  final Color borderStrong;

  /// Ambient shadow that lifts floating chrome (e.g. the bottom tab bar) off
  /// the page. Transparent in dark mode — there the `surface`/`bg` contrast
  /// already separates the bar, and a black shadow is invisible on black.
  final Color shadow;

  /// Green for accents drawn *on top of* a surface as text, icons or outlines
  /// (e.g. the Add-Account button, the selected bottom-tab item). Light
  /// [primary] is a bright lime that washes out on white, so light mode uses a
  /// darker, more saturated green here instead; dark mode matches [primary],
  /// which already reads on the dark surface.
  final Color accent;

  const ColorTokens({
    required this.primary,
    required this.bg,
    required this.groupedBg,
    required this.surface,
    required this.text,
    required this.error,
    required this.onPrimary,
    required this.onBg,
    required this.border,
    required this.borderStrong,
    required this.shadow,
    required this.accent,
  });

  static const dark = ColorTokens(
    primary: Color(0xFFA1F44E),
    bg: Color(0xFF000000),
    groupedBg: Color(0xFF000000),
    surface: Color(0xFF1A1A1A),
    text: Color(0xFFFFFFFF),
    error: Color(0xFFCF6679),
    onPrimary: Color(0xFF000000),
    onBg: Color(0xFFFFFFFF),
    border: Color(0xFF333333),
    borderStrong: Color(0xFF333333),
    shadow: Color(0x00000000),
    accent: Color(0xFFA1F44E),
  );

  static const light = ColorTokens(
    primary: Color(0xFF7AE60F),
    bg: Color(0xFFFFFFFF),
    groupedBg: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF212121),
    error: Color(0xFFB00020),
    onPrimary: Color(0xFF000000),
    onBg: Color(0xFF212121),
    border: Color(0xFFD1D1D6),
    borderStrong: Color(0xFF000000),
    shadow: Color(0x0C000000),
    accent: Color(0xFF15803D),
  );
}

/// Corner radius constants matching open-ledger-mono design system.
///
/// - [sm] = 6.0 — small corners (cards, inputs)
/// - [lg] = 12.0 — medium corners (buttons, dialogs)
/// - [xl] = 18.0 — large corners (sheets, panels)
///
/// No `R.md` — use [lg] for medium corners.
class R {
  R._();

  static const double sm = 6.0;
  static const double lg = 12.0;
  static const double xl = 18.0;
}
