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

  /// Tinted background for inset grouped lists (e.g. Settings): pure black in
  /// dark mode, a pale lime tint (`hsl(84, 71%, 89%)` = `#E7F7CF`) in light.
  /// Cards ([surface]) sit on top of it without needing their own border.
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

  /// Foreground for content drawn on a solid [accent] fill.
  ///
  /// Not [onPrimary]: that is tuned for light [primary] (a bright lime, so
  /// black text), whereas light [accent] is a deep green that needs white. Dark
  /// [accent] is the lime [primary], so the two agree there by coincidence.
  final Color onAccent;

  /// Whether this theme uses the neobrutalist chrome (see `Neo`).
  ///
  /// Neo is a light-mode language: the block grammar rests on a pure black edge
  /// and a blur-free offset shadow against a light page. On the near-black dark
  /// page the same treatment collapses into low-contrast mush, so dark mode
  /// keeps the original flat grouped-list chrome and screens fall back to it.
  final bool neobrutalism;

  /// Outline colour for neo blocks ([Neo.edge] px, see `widgets/common/neo_*`).
  /// Only read while [neobrutalism] is true.
  ///
  /// Light mode outlines in pure black so the edge reads at maximum contrast on
  /// white.
  final Color neoEdge;

  /// Blur-free offset shadow colour for neo blocks. Only read while
  /// [neobrutalism] is true.
  ///
  /// Deliberately weaker than [neoEdge], so the edge stays the dominant line
  /// and the offset reads as a ledge rather than a second border.
  final Color neoShadow;

  /// Fill for the brand neo action (the Vault "Add Account" button). Only read
  /// while [neobrutalism] is true.
  ///
  /// Fills with the bright [primary] lime — [accent] is for text and icons, not
  /// for a large fill.
  ///
  /// Must stay opaque: a `BoxDecoration` paints its shadow *under* the fill, so
  /// a transparent fill would let the button's own offset shadow show through
  /// its interior.
  final Color actionFill;

  /// Brand ink for neo outlines and labels. Only read while [neobrutalism] is
  /// true.
  ///
  /// Used by the Vault chain-section outline and by the Add-Account button's
  /// outline and label. Light mode uses pure black, because the lime [primary]
  /// washes out against white.
  final Color brandInk;

  /// Line colour of the reference grid painted behind the main tabs (see
  /// `GridBackground`). Only read while [neobrutalism] is true.
  ///
  /// Mid grey at 20% — the value neobrutalism.dev uses (`#80808033`) — so the
  /// lines register as paper ruling on [groupedBg] without competing with the
  /// black card outlines.
  final Color gridLine;

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
    required this.onAccent,
    required this.neobrutalism,
    required this.neoEdge,
    required this.neoShadow,
    required this.actionFill,
    required this.brandInk,
    required this.gridLine,
  });

  /// Text one step down from [text]: full-strength ink under neo, a muted tint
  /// in dark mode.
  ///
  /// [darkAlpha] is the tint's alpha. It is a parameter because the pre-neo
  /// dark greys were tuned per screen by eye (80…200), so passing the original
  /// value through keeps every screen pixel-identical while the neo half of the
  /// decision — "secondary text is still full ink" — lives in one place.
  Color mutedText(int darkAlpha) =>
      neobrutalism ? text : text.withAlpha(darkAlpha);

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
    // Black text on the lime accent, matching `onPrimary`.
    onAccent: Color(0xFF000000),
    // Neo chrome is light-mode only; dark keeps the original flat cards. The
    // neo colours below mirror the light values and are never read.
    neobrutalism: false,
    neoEdge: Color(0xFF000000),
    neoShadow: Color(0xFF000000),
    actionFill: Color(0xFF7AE60F),
    brandInk: Color(0xFF000000),
    gridLine: Color(0x33808080),
  );

  static const light = ColorTokens(
    primary: Color(0xFF7AE60F),
    bg: Color(0xFFFFFFFF),
    groupedBg: Color(0xFFE7F7CF),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF212121),
    error: Color(0xFFB00020),
    onPrimary: Color(0xFF000000),
    onBg: Color(0xFF212121),
    border: Color(0xFFD1D1D6),
    borderStrong: Color(0xFF000000),
    shadow: Color(0x0C000000),
    accent: Color(0xFF15803D),
    // White text on the deep-green accent (black would sit at ~3.4:1).
    onAccent: Color(0xFFFFFFFF),
    neobrutalism: true,
    neoEdge: Color(0xFF000000),
    neoShadow: Color(0xFF000000),
    // Bright lime fill (same value as `primary`) with black text.
    actionFill: Color(0xFF7AE60F),
    // Black outline/label: lime on white would wash out.
    brandInk: Color(0xFF000000),
    // Mid grey at 20%, the reference grid value from neobrutalism.dev.
    gridLine: Color(0x33808080),
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

/// Structural metrics for the neobrutalist chrome used on the Vault and
/// Account Detail screens.
///
/// A "neo block" is a surface outlined by [ColorTokens.borderStrong] at [edge]
/// px, using [radius] corners and lifted off the page by a blur-free shadow
/// offset [lift] px on both axes. On press the block translates by [lift]
/// toward that shadow, so it reads as a physical key being pushed in.
///
/// Colours are never literal here — a neo block outlines in
/// [ColorTokens.borderStrong] (pure black in light, neutral grey in dark) and
/// fills with [ColorTokens.accent] / [ColorTokens.onPrimary].
class Neo {
  Neo._();

  /// Outline width for every neo block (cards, tiles, buttons, badges).
  static const double edge = 2.0;

  /// Hard shadow offset, in logical pixels, on each axis.
  static const double lift = 4.0;

  /// Corner radius for neo blocks — tighter than [R.lg].
  static const double radius = R.sm;

  /// Cell size of the reference grid painted behind the main tabs — the
  /// `70px 70px` step neobrutalism.dev uses. Both axes rule at this interval
  /// in [ColorTokens.gridLine].
  static const double gridStep = 70.0;
}
