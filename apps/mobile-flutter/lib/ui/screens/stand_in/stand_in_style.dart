import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// Secondary-text colour for the stand-in screen, tuned per theme so body/value
/// copy clears WCAG AA contrast (4.5:1).
///
/// A single alpha cannot serve both backgrounds: on light, `text` is
/// near-black on white, so the 130–150 alpha used pre-review lands at only
/// ~3.3–4.2:1. Light therefore takes the higher value; dark keeps a lower
/// alpha so secondary copy still reads softer than primary.
///
/// Shared by every `stand_in/components` and `stand_in/views` block, which each
/// resolve the [Brightness] from the ambient theme.
Color standInSecondaryText(ColorTokens c, Brightness brightness) =>
    c.text.withAlpha(brightness == Brightness.dark ? 160 : 190);
