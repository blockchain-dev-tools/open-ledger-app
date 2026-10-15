import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/color_tokens.dart';

/// The white QR card shared by the export screens: a [Center] holding a
/// white, padded block with a [QrImageView].
///
/// The block stays literal white in both themes — black-on-white is REQUIRED
/// for QR scannability. Under [ColorTokens.neobrutalism] it is outlined as a
/// neo block; dark keeps the hairline that stops it vanishing on the white
/// background.
class QrDisplayCard extends StatelessWidget {
  /// Payload encoded into the QR (mnemonic, private key, address…).
  final String data;

  /// QR edge length in logical pixels.
  final double size;

  const QrDisplayCard({
    super.key,
    required this.data,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Black-on-white is REQUIRED for QR scannability.
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            c.neobrutalism ? Neo.radius : R.lg,
          ),
          // Light mode outlines the white card as a neo block; dark keeps
          // the hairline that stops it vanishing on the white background.
          border: c.neobrutalism
              ? Border.all(color: c.neoEdge, width: Neo.edge)
              : Border.all(color: c.border),
        ),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
