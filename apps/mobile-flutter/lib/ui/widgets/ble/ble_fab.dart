import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/interfaces/chain_ble_control.dart';
import '../../../core/models/ble_types.dart';
import '../../../core/models/chain.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';

/// The single BLE control for the Vault screen — a floating button pinned
/// over the bottom-right of the account list.
///
/// Design: the disc carries the active chain's own logo, and fills with the
/// brand colour while the radio is on (broadcasting or connected) — the
/// fill, not the mark, is what encodes on/off. A ring around the disc
/// encodes the state: dashed = idle, pulsing = broadcasting, solid + check =
/// connected. When idle no chain is exposed, so the disc shows a bluetooth
/// glyph.
class BleFab extends StatefulWidget {
  final IChainBleControl control;
  final VoidCallback onTap;

  const BleFab({super.key, required this.control, required this.onTap});

  @override
  State<BleFab> createState() => _BleFabState();
}

class _BleFabState extends State<BleFab> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse(bool on, bool disabled) {
    if (on && !disabled) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: widget.control,
      builder: (context, _) {
        final state = widget.control.bleState;
        final activeChain = widget.control.activeChain;
        final broadcasting = state == BleState.broadcasting;
        final connected = state == BleState.connected;
        final error = state == BleState.error;
        final disabled = widget.control.isSignPending;
        // "On" = the radio is live. It drives the solid brand fill.
        final on = broadcasting || connected;
        _syncPulse(broadcasting, disabled);

        // Tone for marks drawn ON the brand fill (badge check).
        final Color onPrimary = c.onPrimary;

        // The ring's SHAPE encodes BLE state (pulse / solid / dashed) and
        // must stay truthful even when disabled — a signing request must not
        // make the device look disconnected. Only the colour is muted when
        // the control is locked.
        final Color ringColor = error
            ? (disabled ? c.text.withAlpha(70) : c.error)
            : (broadcasting || connected)
                ? (disabled ? c.text.withAlpha(70) : c.primary)
                : (disabled ? c.text.withAlpha(25) : c.text.withAlpha(45));

        final String tooltip = disabled
            ? l10n.signPending
            : (broadcasting || connected)
                ? l10n.blePeripheral
                : l10n.startBle;

        return Semantics(
          button: true,
          label: tooltip,
          child: SizedBox(
            // The box is only as large as the widest ripple, so the disc
            // itself can stay small while the "on" ripple breathes outward.
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // ── State ring ─────────────────────────────────────
                // Broadcasting breathes; idle is a dashed "not yet on";
                // connected/error are a solid stroke.
                if (broadcasting)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final t = Curves.easeInOut.transform(_pulse.value);
                      // Wide travel with a gentle fade and taper: the ring
                      // stays legible all the way out — a ripple, not a
                      // vanishing border.
                      return Container(
                        width: 52 + t * 22,
                        height: 52 + t * 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: disabled
                                ? c.text.withAlpha(150 - (t * 90).round())
                                : c.primary.withAlpha(230 - (t * 120).round()),
                            width: 2 - t * 0.7,
                          ),
                        ),
                      );
                    },
                  )
                else if (error || connected)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ringColor,
                        width: 2,
                      ),
                    ),
                  )
                else
                  _DashedRing(
                    size: 56,
                    color: ringColor,
                  ),

                // ── Main disc ──────────────────────────────────────
                Material(
                  color: disabled
                      ? c.text.withAlpha(22)
                      : on
                          ? c.primary
                          : c.surface,
                  // The idle disc is a neutral fill, which in light mode is
                  // white-on-white — the fill alone disappears, so the disc
                  // carries its own outline. `c.border` is too close to the
                  // page colour to register, hence the toned-down text token.
                  // The brand fill needs no outline of its own.
                  shape: on || disabled
                      ? const CircleBorder()
                      : CircleBorder(
                          side: BorderSide(color: c.text.withAlpha(60)),
                        ),
                  elevation: disabled ? 0 : 3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: disabled ? null : widget.onTap,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: _buildGlyph(
                          c,
                          activeChain,
                          error,
                          disabled,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Connected badge ────────────────────────────────
                // Kept while pending (muted) so the user can tell the link
                // is still up even though the button is locked. On a brand
                // fill it inverts (bg disc + brand check) to stay visible.
                if (connected)
                  Positioned(
                    right: 13,
                    bottom: 13,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: disabled
                            ? c.text.withAlpha(70)
                            : on
                                ? c.bg
                                : c.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.bg, width: 2),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 10,
                        color: (on && !disabled) ? c.primary : onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlyph(
    ColorTokens c,
    Chain? activeChain,
    bool error,
    bool disabled,
  ) {
    // The mark fills most of the (small) disc — it should read as the
    // button's subject, not as a small sticker on a big circle.
    const double glyph = 30;
    if (error) {
      return Icon(Icons.bluetooth_disabled,
          color: disabled ? c.text.withAlpha(60) : c.error, size: glyph);
    }
    if (activeChain != null) {
      // The chain logo keeps its own colours in every state — the disc fill
      // (neutral vs brand) is what encodes on/off, not the mark.
      final logo = SvgPicture.asset(
        activeChain.iconAssetPath,
        width: glyph,
        height: glyph,
      );
      if (!disabled) return logo;
      // Locked: mute to grey so it reads as "temporarily unavailable".
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
        child: logo,
      );
    }
    return Icon(Icons.bluetooth,
        color: disabled ? c.text.withAlpha(60) : c.text.withAlpha(130),
        size: glyph);
  }
}

/// Dashed circular outline used for the idle state — Flutter's [Border]
/// cannot dash, so the arc segments are painted directly.
class _DashedRing extends StatelessWidget {
  final double size;
  final Color color;

  const _DashedRing({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _DashPainter(color),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  static const int _segments = 26;
  static const double _drawnFraction = 0.5;

  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    final segment = 2 * 3.141592653589793 / _segments;
    for (var i = 0; i < _segments; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * segment,
        segment * _drawnFraction,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}
