import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// The blur-free offset shadow that gives a neo block its hard edge.
///
/// Zero blur is the point: the shadow is a second outline rather than a
/// soft drop, which is what separates neobrutalism from a Material elevation.
List<BoxShadow> neoShadow(ColorTokens c) => <BoxShadow>[
      BoxShadow(
        color: c.neoShadow,
        offset: const Offset(Neo.lift, Neo.lift),
        blurRadius: 0,
      ),
    ];

/// A card that speaks two chrome languages.
///
/// While [ColorTokens.neobrutalism] is true it is a hard-edged block: [Neo.edge]
/// px of [ColorTokens.neoEdge] outline, [Neo.radius] corners and a single
/// blur-free shadow ([neoShadow]) offset [Neo.lift] on both axes. Unlike a
/// [Material] card it paints no ripple; press feedback belongs to the
/// interactive children ([NeoButton]).
///
/// Otherwise it falls back to the flat, pre-neo card described by the `legacy*`
/// parameters, so dark mode keeps the chrome it had before the neo experiment.
///
/// ```dart
/// NeoCard(padding: const EdgeInsets.all(16), child: Text('Address'))
/// ```
class NeoCard extends StatelessWidget {
  /// Content laid out inside the block.
  final Widget child;

  /// Inner padding. When `null` the child manages its own — the Vault
  /// accordion needs its header flush with the outline so the expanded
  /// section's fill reaches the corners.
  final EdgeInsetsGeometry? padding;

  /// Outer spacing. Reserve at least [Neo.lift] on the right and bottom so a
  /// stacked block has room for its shadow.
  final EdgeInsetsGeometry margin;

  /// Clips the child to the corner radius — required whenever a child fills
  /// the block edge to edge.
  final bool clip;

  /// Keeps the outline but drops the shadow, for small tiles that sit *on*
  /// another neo block (chain icons, account-number chips). Ignored by the
  /// legacy chrome, which never draws a shadow.
  final bool lifted;

  /// Neo outline colour. Defaults to [ColorTokens.neoEdge]; pass
  /// [ColorTokens.brandInk] for blocks outlined in the brand colour.
  final Color? edge;

  /// Legacy outline colour. Defaults to [ColorTokens.borderStrong].
  final Color? legacyEdge;

  /// Legacy outline width in px, for cards whose pre-neo outline varied with
  /// state (the Vault section is 2px while expanded). Zero removes it.
  final double legacyEdgeWidth;

  /// Legacy corner radius. Defaults to [R.lg].
  final double legacyRadius;

  /// Legacy fill. Defaults to [ColorTokens.surface]; the tinted icon tiles
  /// restore their translucent fill through this.
  final Color? legacyBackground;

  const NeoCard({
    super.key,
    required this.child,
    this.padding,
    this.margin = EdgeInsets.zero,
    this.clip = false,
    this.lifted = true,
    this.edge,
    this.legacyEdge,
    this.legacyEdgeWidth = 1,
    this.legacyRadius = R.lg,
    this.legacyBackground,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final body =
        padding == null ? child : Padding(padding: padding!, child: child);

    final BoxDecoration decoration;
    if (c.neobrutalism) {
      decoration = BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Neo.radius),
        border: Border.all(color: edge ?? c.neoEdge, width: Neo.edge),
        boxShadow: lifted ? neoShadow(c) : null,
      );
    } else {
      decoration = BoxDecoration(
        color: legacyBackground ?? c.surface,
        borderRadius: BorderRadius.circular(legacyRadius),
        border: legacyEdgeWidth == 0
            ? null
            : Border.all(
                color: legacyEdge ?? c.borderStrong,
                width: legacyEdgeWidth,
              ),
      );
    }

    return Container(
      margin: margin,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: decoration,
      child: body,
    );
  }
}
