import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import 'neo_rule.dart';
import 'neo_sheet.dart';

/// One row in a [showNeoOptionSheet]: what it reads, whether it is the current
/// value, and what to run when it is picked.
typedef NeoSheetOption = ({String label, bool selected, VoidCallback onSelect});

/// Shows the app's standard single-select option sheet (display mode, display
/// language, BIP-39 wordlist, launcher disguise).
///
/// Neo-aware: light mode draws a hard [Neo.edge] outline in
/// [ColorTokens.neoEdge] with the tighter [Neo.radius] corners, a black grab
/// handle and a bold title, and marks the current value with a
/// [ColorTokens.actionFill] band; dark keeps the original soft, rounded sheet
/// with the neutral handle and a brand-coloured check.
void showNeoOptionSheet({
  required BuildContext context,
  required String title,
  required List<NeoSheetOption> options,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final c = isDark ? ColorTokens.dark : ColorTokens.light;
  final neo = c.neobrutalism;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    shape: neoSheetShape(c),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // Narrower than the BLE panel's handle.
            neoSheetHandle(c, width: 36),
            // The title's gap to the boundary below it (the neo rule, or the
            // first option in dark) — well clear of the original sheet's 6px.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Text(
                title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 17,
                  fontWeight: neo ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            // Neo rules a heavy line under the title — twice the option
            // separator's weight — and bounds every option. Dark keeps the
            // original undivided sheet.
            if (neo) neoRule(c, heavy: true),
            for (final (i, opt) in options.indexed) ...[
              InkWell(
                onTap: () {
                  Navigator.of(ctx).pop();
                  opt.onSelect();
                },
                child: Container(
                  // Neo marks the current value with a lime band; dark relies
                  // on the check alone.
                  color: neo && opt.selected ? c.actionFill : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt.label,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            fontWeight: opt.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (opt.selected)
                        Icon(
                          Icons.check_rounded,
                          color: neo ? c.brandInk : c.primary,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
              if (neo && i < options.length - 1) neoRule(c),
            ],
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
