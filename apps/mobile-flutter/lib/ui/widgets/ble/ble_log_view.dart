import 'package:flutter/material.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../theme/color_tokens.dart';
import '../common/neo_rule.dart';
import 'ble_log_controller.dart';
import 'ble_log_row.dart';

/// The live BLE activity log, rendered as the second *view* inside the BLE
/// control sheet — never as a second bottom sheet stacked on top of it
/// (house rule: no sheet-on-sheet).
///
/// The [controller] is session-scoped (owned by MainScreen), so switching
/// views back and forth never drops or replays entries. [onBack] returns
/// to the control view within the same sheet.
class BleLogView extends StatelessWidget {
  final BleLogController controller;
  final ColorTokens c;
  final VoidCallback onBack;

  const BleLogView({
    super.key,
    required this.controller,
    required this.c,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: c.neobrutalism ? c.brandInk : c.text.withAlpha(180)),
                tooltip: l10n.back,
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.bleLogs,
                style: TextStyle(
                  color: c.neobrutalism ? c.brandInk : c.text,
                  fontSize: 15,
                  // Neo gives the view title the same weight as the control
                  // view's header.
                  fontWeight:
                      c.neobrutalism ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        // Neo rules the header off with a black line, matching the control
        // view; dark keeps the hairline.
        neoRule(c),
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final entries = controller.entries;
              if (entries.isEmpty) {
                return Center(
                  child: Text(
                    l10n.noBleActivity,
                    style: TextStyle(
                      color: c.neobrutalism ? c.brandInk : c.text.withAlpha(100),
                      fontSize: 14,
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: entries.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: BleLogRow(entry: entries[i], c: c),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
