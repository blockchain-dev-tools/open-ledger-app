import 'dart:async';

import 'package:flutter/material.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';

/// Auto-hide affordance shared by the seed / private-key reveal screens.
///
/// Counts [seconds] down to zero and fires [onElapsed] once, so a secret left
/// on screen closes itself. Gallery previews pass [previewSeconds] to freeze
/// the display: screenshots stay deterministic and no timer runs.
class AutoHideCountdown extends StatefulWidget {
  const AutoHideCountdown({
    super.key,
    required this.seconds,
    this.previewSeconds,
    this.onElapsed,
  });

  /// Full countdown length.
  final int seconds;

  /// Frozen remaining seconds (design gallery). When set, no timer runs.
  final int? previewSeconds;

  /// Called once when the countdown reaches zero.
  final VoidCallback? onElapsed;

  @override
  State<AutoHideCountdown> createState() => _AutoHideCountdownState();
}

class _AutoHideCountdownState extends State<AutoHideCountdown> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.previewSeconds ?? widget.seconds;
    if (widget.previewSeconds == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining--);
        if (_remaining <= 0) {
          _timer?.cancel();
          widget.onElapsed?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final total = widget.seconds <= 0 ? 1 : widget.seconds;
    final fraction = (_remaining / total).clamp(0.0, 1.0);

    // Light mode outlines the track as a neo block with the brand lime fill;
    // dark keeps the original bare bar.
    final bar = c.neobrutalism
        ? Container(
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(Neo.radius),
              border: Border.all(color: c.neoEdge, width: Neo.edge),
            ),
            clipBehavior: Clip.antiAlias,
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: c.bg,
              valueColor: AlwaysStoppedAnimation<Color>(c.actionFill),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: c.text.withAlpha(30),
              valueColor: AlwaysStoppedAnimation<Color>(c.primary),
            ),
          );

    return Column(
      children: [
        Text(
          AppLocalizations.of(context)!.autoHideHint(_remaining),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.mutedText(120),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        bar,
      ],
    );
  }
}
