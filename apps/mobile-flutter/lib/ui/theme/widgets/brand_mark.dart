import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The D8 OpenLedger mark. Each theme has its own background and foreground.
class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      isDark
          ? 'assets/icons/brand/open-ledger-dark.svg'
          : 'assets/icons/brand/open-ledger-light.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: 'OpenLedger',
    );
  }
}
