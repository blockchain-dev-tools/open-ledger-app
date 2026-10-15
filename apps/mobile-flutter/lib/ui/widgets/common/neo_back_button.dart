import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// The back affordance a pushed page puts in its [neoAppBar].
///
/// The glyph follows the theme's text colour, so neo reads as ink and dark
/// keeps the grey it had. [onPressed] is whatever the page means by "back" —
/// a pop, or a `go` for a step that must not return to the previous one.
Widget neoBackButton(ColorTokens c, {required VoidCallback onPressed}) =>
    IconButton(
      icon: Icon(Icons.arrow_back, color: c.text),
      onPressed: onPressed,
    );
