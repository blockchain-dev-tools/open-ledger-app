/// A single BLE log row.
///
/// Expandable when the entry carries a [BleLogEntry.detail] (raw hex):
/// tap reveals the detail; collapsed by default. Plain text otherwise.
library;

import 'package:flutter/material.dart';

import '../../../core/models/ble_log_entry.dart';
import '../../theme/color_tokens.dart';

class BleLogRow extends StatefulWidget {
  final BleLogEntry entry;
  final ColorTokens c;

  const BleLogRow({super.key, required this.entry, required this.c});

  @override
  State<BleLogRow> createState() => _BleLogRowState();
}

class _BleLogRowState extends State<BleLogRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final c = widget.c;
    // Neo inks plain entries black; errors and warnings keep their signal.
    final color = e.level == BleLogLevel.error
        ? c.error
        : e.level == BleLogLevel.warn
            ? c.error.withAlpha(170)
            : c.neobrutalism
                ? c.brandInk
                : c.text.withAlpha(180);
    final mono = TextStyle(
      color: color,
      fontSize: 12,
      fontFamily: 'monospace',
    );

    // Pending response — in-flight placeholder with a spinner. Replaced
    // in place when the matching `sent` / `send error` line arrives.
    if (e.status == BleLogStatus.pending) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              // Neo reads as ink; lime on white would wash out.
              color: c.neobrutalism ? c.neoEdge : c.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              e.summary,
              style: TextStyle(
                color: c.neobrutalism ? c.brandInk : c.text.withAlpha(150),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      );
    }

    // Non-expandable line — plain text, same as before.
    if (e.detail == null) {
      return Text(e.summary, style: mono);
    }

    // Expandable line — tap to reveal the raw encoding.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(e.summary, style: mono)),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 4),
              child: Text(
                e.detail!,
                style: TextStyle(
                  color: c.text.withAlpha(140),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
