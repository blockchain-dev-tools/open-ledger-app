import 'package:flutter/material.dart';

import '../../../core/interfaces/screen_security.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';

/// Blanket that hides its child whenever the app leaves the foreground, while
/// holding the OS screenshot flag down for as long as it is mounted
/// (ADR-011 §6).
///
/// A secret on screen must not survive in the recents thumbnail or a
/// screenshot: going to the background paints an opaque cover immediately and
/// coming back restores the screen unchanged. The covered state is *only* a
/// visual shield — the PIN gate has already run, so nothing is re-derived or
/// re-revealed on return.
///
/// Wrap the screens that display a secret, not the whole app: this is the
/// envelope around controlled display.
class PrivacyShield extends StatefulWidget {
  const PrivacyShield({
    super.key,
    required this.child,
    this.screenSecurity,
    this.previewHidden = false,
  });

  final Widget child;

  /// Platform screenshot-flag toggle. `null` (gallery / tests) leaves only
  /// the lifecycle cover in play.
  final IScreenSecurity? screenSecurity;

  /// Freezes the covered state so the design gallery can capture it.
  final bool previewHidden;

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  /// Whether the app is currently away from the foreground.
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Held for the whole time the secret is on screen, not just while hidden:
    // a foreground screenshot of a revealed phrase is exactly what this
    // blocks.
    widget.screenSecurity?.enable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.screenSecurity?.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final backgrounded = state != AppLifecycleState.resumed;
    if (backgrounded != _backgrounded) {
      setState(() => _backgrounded = backgrounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = widget.previewHidden || _backgrounded;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (hidden) const _ShieldCover(),
      ],
    );
  }
}

/// Opaque cover shown in place of the secret.
class _ShieldCover extends StatelessWidget {
  const _ShieldCover();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return ColoredBox(
      color: c.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 44, color: c.text.withAlpha(120)),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context)!.privacyShield,
              style: TextStyle(color: c.text.withAlpha(140), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
