import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/models/chain.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../utils/formatting.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/neo_rule.dart';
import '../../../widgets/common/neo_sheet.dart';

/// Bottom sheet for turning chains on and off ("Manage chains").
///
/// One switch per chain, seeded from [visible]. Turning a chain on derives its
/// account 0 through [onToggle]; turning it off keeps the accounts and only
/// hides the chain from the Vault and the BLE picker.
class ManageChainsSheet extends StatefulWidget {
  /// Chain ids currently shown in the Vault.
  final Set<String> visible;

  /// Applies the change; returns false when it failed (the switch snaps back).
  final Future<bool> Function(Chain chain, bool visible) onToggle;

  const ManageChainsSheet({
    super.key,
    required this.visible,
    required this.onToggle,
  });

  @override
  State<ManageChainsSheet> createState() => _ManageChainsSheetState();
}

class _ManageChainsSheetState extends State<ManageChainsSheet> {
  late final Set<String> _visible = {...widget.visible};

  /// Chains with an in-flight derive/persist — their switch is disabled so a
  /// second tap cannot race the first.
  final Set<String> _busy = {};

  Future<void> _toggle(Chain chain) async {
    if (_busy.contains(chain.id)) return;
    final next = !_visible.contains(chain.id);
    setState(() => _busy.add(chain.id));
    try {
      final ok = await widget.onToggle(chain, next);
      if (!mounted) return;
      if (ok) {
        setState(() {
          next ? _visible.add(chain.id) : _visible.remove(chain.id);
        });
      }
    } finally {
      if (mounted) setState(() => _busy.remove(chain.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final chains = Chain.withLedgerApp;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            neoSheetHandle(c),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.manageChainsSheetTitle,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: c.neobrutalism
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('manage-chains-close'),
                    icon: Icon(Icons.close, color: c.mutedText(140)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (c.neobrutalism) neoRule(c, heavy: true),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        l10n.manageChainsSheetHint,
                        style: TextStyle(
                          color: c.mutedText(150),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                    for (final chain in chains) ...[
                      _ManageChainRow(
                        chain: chain,
                        label: l10n.chainLabel(chain.id),
                        tokens: c,
                        shown: _visible.contains(chain.id),
                        busy: _busy.contains(chain.id),
                        onToggle: () => _toggle(chain),
                      ),
                      if (c.neobrutalism && chain != chains.last) neoRule(c),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageChainRow extends StatelessWidget {
  final Chain chain;
  final String label;
  final ColorTokens tokens;
  final bool shown;
  final bool busy;
  final VoidCallback onToggle;

  const _ManageChainRow({
    required this.chain,
    required this.label,
    required this.tokens,
    required this.shown,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final neo = tokens.neobrutalism;
    final icon = SvgPicture.asset(chain.iconAssetPath, width: 24, height: 24);
    final toggle = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.accent,
            ),
          )
        : neo
        // 日间模式把开关画成 neo 块：黑描边 + lime 轨道 + 黑滑块。
        ? SwitchTheme(
            data: SwitchThemeData(
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? tokens.actionFill
                    : tokens.surface,
              ),
              trackOutlineColor: WidgetStatePropertyAll(tokens.neoEdge),
              trackOutlineWidth: const WidgetStatePropertyAll(Neo.edge),
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? tokens.brandInk
                    : tokens.text.withAlpha(90),
              ),
            ),
            child: _switch(),
          )
        : _switch();

    return InkWell(
      key: ValueKey('chain-toggle-row-${chain.id}'),
      onTap: busy ? null : onToggle,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: neo ? 7 : 4, horizontal: 4),
        child: Row(
          children: [
            if (neo)
              NeoCard(
                lifted: false,
                padding: const EdgeInsets.all(5),
                child: icon,
              )
            else
              icon,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: tokens.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            toggle,
          ],
        ),
      ),
    );
  }

  Widget _switch() => Switch(
    key: ValueKey('chain-toggle-${chain.id}'),
    value: shown,
    onChanged: busy ? null : (_) => onToggle(),
  );
}
