import 'package:flutter/material.dart';

import '../../../../core/models/wallet_accounts.dart';
import '../../../../generated/l10n/app_localizations.dart';
import '../../../../utils/formatting.dart';
import '../../../theme/color_tokens.dart';
import '../../../widgets/common/copy_to_clipboard.dart';
import '../../../widgets/common/neo_button.dart';
import '../../../widgets/common/neo_card.dart';
import '../../../widgets/common/neo_code_block.dart';

/// One "Details" card with two rows (label left / value right, monospace):
/// derivation path, and a collapsible public key.
class AccountDetailsCard extends StatefulWidget {
  final ChainAccount account;

  const AccountDetailsCard({super.key, required this.account});

  @override
  State<AccountDetailsCard> createState() => _AccountDetailsCardState();
}

class _AccountDetailsCardState extends State<AccountDetailsCard> {
  /// Whether the public key hex is expanded (default: collapsed).
  bool _publicKeyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final l10n = AppLocalizations.of(context)!;
    final account = widget.account;

    return NeoCard(
      clip: true,
      // Dark restores the original hairline card.
      legacyEdge: c.border.withAlpha(80),
      child: Column(
        children: [
          _buildDetailRow(
            c,
            label: l10n.derivationPath,
            value: account.derivationPath,
          ),
          if (c.neobrutalism)
            Divider(height: Neo.edge, thickness: Neo.edge, color: c.neoEdge)
          else
            Divider(height: 1, color: c.border),
          if (account.publicKey.isNotEmpty)
            _buildPublicKeyRow(context, c, account.publicKey),
        ],
      ),
    );
  }

  /// A non-interactive `label left / value right` row.
  Widget _buildDetailRow(
    ColorTokens c, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: c.text.withAlpha(120), fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.text,
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsible public key row. Collapsed → middle-truncated `first8…last6`
  /// + copy icon + "Show more"; tap toggles full wrapped hex + "Show less".
  Widget _buildPublicKeyRow(
    BuildContext context,
    ColorTokens c,
    String pubKey,
  ) {
    final l10n = AppLocalizations.of(context)!;

    if (!_publicKeyExpanded) {
      return InkWell(
        onTap: () => setState(() => _publicKeyExpanded = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n.publicKey,
                    style:
                        TextStyle(color: c.text.withAlpha(120), fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      truncateMiddle(pubKey),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _copyIcon(context, c, pubKey),
                ],
              ),
              SizedBox(height: c.neobrutalism ? 10.0 : 6.0),
              if (c.neobrutalism)
                NeoButton(
                  key: const ValueKey('public-key-expand'),
                  label: l10n.showMore,
                  icon: Icons.unfold_more,
                  quiet: true,
                  onTap: () => setState(() => _publicKeyExpanded = true),
                )
              else
                Text(
                  l10n.showMore,
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.publicKey,
                style: TextStyle(color: c.text.withAlpha(120), fontSize: 13),
              ),
              const Spacer(),
              _copyIcon(context, c, pubKey),
            ],
          ),
          const SizedBox(height: 8),
          NeoCodeBlock(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              pubKey,
              style: TextStyle(
                color: c.text.withAlpha(180),
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
          SizedBox(height: c.neobrutalism ? 10.0 : 8.0),
          if (c.neobrutalism)
            NeoButton(
              key: const ValueKey('public-key-collapse'),
              label: l10n.showLess,
              icon: Icons.unfold_less,
              quiet: true,
              onTap: () => setState(() => _publicKeyExpanded = false),
            )
          else
            InkWell(
              onTap: () => setState(() => _publicKeyExpanded = false),
              child: Text(
                l10n.showLess,
                style: TextStyle(
                  color: c.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Small inline copy affordance (icon only, ripple).
  Widget _copyIcon(BuildContext context, ColorTokens c, String text) {
    return InkWell(
      onTap: () => copyToClipboard(context, text),
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.copy, size: 16, color: c.text.withAlpha(100)),
      ),
    );
  }
}
