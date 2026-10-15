import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// A selectable address with its first six and last six characters emphasised
/// in the theme's highlight colour.
///
/// [ColorTokens.accent] is used rather than the brand lime: the lime washes out
/// on the white neo page while the deeper accent green stays legible. Short
/// addresses (≤ 12 chars) are rendered whole and undifferentiated.
class HighlightedAddressText extends StatelessWidget {
  /// The full address to render.
  final String address;

  /// Colour tokens for the active theme.
  final ColorTokens c;

  const HighlightedAddressText({
    super.key,
    required this.address,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      _span(),
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
    );
  }

  /// Build a [TextSpan] with first 6 and last 6 chars bold+primary.
  TextSpan _span() {
    // Light's lime highlights wash out on white; the accent green stands in.
    final highlight = c.accent;
    if (address.length <= 12) {
      return TextSpan(text: address, style: TextStyle(color: c.text));
    }
    final prefix = address.substring(0, 6);
    final middle = address.substring(6, address.length - 6);
    final suffix = address.substring(address.length - 6);
    return TextSpan(
      children: [
        TextSpan(
          text: prefix,
          style: TextStyle(color: highlight, fontWeight: FontWeight.bold),
        ),
        TextSpan(text: middle, style: TextStyle(color: c.text)),
        TextSpan(
          text: suffix,
          style: TextStyle(color: highlight, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
