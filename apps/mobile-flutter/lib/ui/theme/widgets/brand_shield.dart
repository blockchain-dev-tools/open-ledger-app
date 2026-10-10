import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Open Ledger App brand mark — a line-art shield with a keyhole.
///
/// Renders `assets/icons/brand/shield-lock.svg`, tinted with the theme's
/// primary color so it follows dark/light mode automatically.
/// Used on the Welcome and Unlock screens.
class BrandShield extends StatelessWidget {
  /// Width and height of the mark in logical pixels.
  final double size;

  const BrandShield({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/brand/shield-lock.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.primary,
        BlendMode.srcIn,
      ),
    );
  }
}
