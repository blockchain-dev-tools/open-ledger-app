import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/pin/pin_dot_indicator.dart';
import '../../../widgets/pin/pin_number_pad.dart';
import '../stand_in_style.dart';

/// Shared PIN prompt for every credential step — the two-pass wizard PIN, the
/// current/new/confirm change-PIN flow, and the main-PIN re-verification for
/// mode / remove actions.
class PinView extends StatelessWidget {
  final ColorTokens c;

  /// Prompt heading, already localized by the shell.
  final String title;

  /// Prompt subtitle; empty when the step has none.
  final String subtitle;

  final int pinLength;

  /// How many dots are currently filled.
  final int filledCount;

  /// Inline validation message, if any.
  final String? pinError;

  final void Function(int digit) onDigit;
  final VoidCallback onBackspace;

  const PinView({
    super.key,
    required this.c,
    required this.title,
    required this.subtitle,
    required this.pinLength,
    required this.filledCount,
    required this.pinError,
    required this.onDigit,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final neo = c.neobrutalism;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Light turns the translucent lime glyph into an outlined neo
              // tile so the lock reads as a hard block; dark keeps the glyph.
              if (neo)
                NeoCard(
                  lifted: false,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(
                      Icons.lock_outline,
                      size: 34,
                      color: c.brandInk,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: c.primary.withAlpha(120),
                ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 20,
                  fontWeight: neo ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    // Neo renders the subtitle in full brand ink, matching the
                    // set-PIN header; dark keeps the muted secondary tone.
                    color: neo
                        ? c.text
                        : standInSecondaryText(
                            c,
                            Theme.of(context).brightness,
                          ),
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              PinDotIndicator(length: pinLength, filledCount: filledCount),
              if (pinError != null) ...[
                const SizedBox(height: 12),
                Text(
                  pinError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.error, fontSize: 14),
                ),
              ],
              const SizedBox(height: 28),
              PinNumberPad(
                onDigit: onDigit,
                onBackspace: onBackspace,
                keyPrefix: 'standin-pin',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
