import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// The shape every neo sheet is opened with.
///
/// Light mode outlines the panel in [ColorTokens.neoEdge] at [Neo.edge] px and
/// pulls the corners in to [Neo.radius]; dark keeps the original soft, rounded
/// sheet with no outline.
///
/// ```dart
/// showModalBottomSheet(context: context, shape: neoSheetShape(c), builder: ...)
/// ```
ShapeBorder neoSheetShape(ColorTokens c) => RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(c.neobrutalism ? Neo.radius : R.xl),
      ),
      side: c.neobrutalism
          ? BorderSide(color: c.neoEdge, width: Neo.edge)
          : BorderSide.none,
    );

/// The grab handle a sheet opens with: a crisp black bar under neo, the grey
/// pill in dark.
///
/// [width] differs per sheet (the option sheet is narrower than the BLE
/// panel), which is the only thing callers vary.
Widget neoSheetHandle(ColorTokens c, {double width = 40}) => Center(
      child: Container(
        width: width,
        height: c.neobrutalism ? 3 : 4,
        decoration: BoxDecoration(
          color: c.neobrutalism ? c.neoEdge : c.text.withAlpha(60),
          borderRadius: BorderRadius.circular(c.neobrutalism ? 0 : 2),
        ),
      ),
    );
