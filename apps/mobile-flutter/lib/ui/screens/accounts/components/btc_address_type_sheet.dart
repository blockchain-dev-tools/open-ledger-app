import 'package:flutter/material.dart';

import '../../../../core/models/bitcoin_address_type.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../utils/formatting.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/neo_rule.dart';
import '../../../widgets/common/neo_sheet.dart';

/// Bottom sheet that picks which Bitcoin address type a new account uses.
///
/// The four types are separate accounts on separate derivation paths, so this
/// is an account-creation choice, not a display format. Pops the chosen
/// [BitcoinAddressType], or `null` when dismissed.
///
/// [paths] carries the concrete derivation path each option will create, so the
/// sheet shows the same path the account is about to be derived at. Each type is
/// its own account family, so the index differs per type.
class BtcAddressTypeSheet extends StatelessWidget {
  final Map<BitcoinAddressType, String> paths;

  const BtcAddressTypeSheet({super.key, required this.paths});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
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
                    l10n.btcAddressTypeTitle,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 17,
                      fontWeight:
                          c.neobrutalism ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('btc-address-type-close'),
                  icon: Icon(Icons.close, color: c.mutedText(140)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (c.neobrutalism) neoRule(c, heavy: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              l10n.btcAddressTypeHint,
              style: TextStyle(
                color: c.mutedText(150),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final type in BitcoinAddressType.values)
                  _TypeRow(
                    type: type,
                    tokens: c,
                    label: l10n.bitcoinAddressTypeLabel(type),
                    path: paths[type] ?? type.pathForIndex(0),
                    onTap: () => Navigator.of(context).pop(type),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  final BitcoinAddressType type;
  final ColorTokens tokens;
  final String label;
  final String path;
  final VoidCallback onTap;

  const _TypeRow({
    required this.type,
    required this.tokens,
    required this.label,
    required this.path,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neo = tokens.neobrutalism;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: neo ? 6 : 6, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.text,
                          fontSize: 15,
                          fontWeight: neo ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      bitcoinAddressTypePrefix(type),
                      style: TextStyle(
                        color: tokens.mutedText(150),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // 具体派生路径：四种类型是四条不同的路径，显示出来才能解释
                // 为什么地址前缀不同。
                Text(
                  path,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.mutedText(140),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: neo ? tokens.brandInk : tokens.text.withAlpha(60),
          ),
        ],
      ),
    );

    return GestureDetector(
      key: ValueKey('btc-address-type-${type.id}'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: neo
          // Room for the hard offset shadow under each block.
          ? NeoCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: row,
            )
          : row,
    );
  }
}
