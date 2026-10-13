import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:open_ledger_app/ui/screens/accounts/components/account_row.dart';
import 'package:open_ledger_app/ui/theme/color_tokens.dart';
import 'package:open_ledger_app/utils/formatting.dart';
import 'package:open_ledger_app/ui/widgets/common/copy_button.dart';
import 'package:open_ledger_app/ui/widgets/common/neo_button.dart';
import 'package:open_ledger_app/ui/widgets/common/neo_card.dart';
import 'package:open_ledger_app/ui/widgets/common/neo_code_block.dart';
import 'package:open_ledger_app/ui/widgets/common/primary_button.dart';
import 'package:open_ledger_app/ui/widgets/common/section_header.dart';
import 'package:open_ledger_app/ui/widgets/mnemonic/warning_banner.dart';
import 'package:open_ledger_app/ui/widgets/pin/pin_dot_indicator.dart';
import 'package:open_ledger_app/ui/widgets/pin/pin_number_pad.dart';

import '../data/sample_accounts.dart';

class ComponentsPage extends StatelessWidget {
  const ComponentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              'COMMON COMPONENTS',
              style: TextStyle(
                color: c.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 20),

            // ── Buttons ──────────────────────────────────────────────
            const SectionHeader(title: 'PrimaryButton'),
            const SizedBox(height: 10),
            PrimaryButton(label: '确认连接 Confirm', onTap: () {}),
            const SizedBox(height: 10),
            const PrimaryButton(label: '禁用态 Disabled', onTap: null),
            const SizedBox(height: 10),
            const PrimaryButton(label: '加载中 Loading', loading: true),
            const SizedBox(height: 10),
            PrimaryButton(
              label: '描边次要 Outline',
              onTap: () {},
              outline: true,
              outlineColor: c.text.withAlpha(140),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: '销毁性操作 Destructive',
              onTap: () {},
              outline: true,
              outlineColor: c.error,
            ),
            const SizedBox(height: 28),

            // ── Copy ─────────────────────────────────────────────────
            const SectionHeader(title: 'CopyButton'),
            const SizedBox(height: 10),
            CopyButton(
              text: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
              label: '复制地址',
              successMessage: '已复制到剪贴板',
            ),
            const SizedBox(height: 28),

            // ── Pin ──────────────────────────────────────────────────
            const SectionHeader(title: 'PinDotIndicator'),
            const SizedBox(height: 14),
            const PinDotIndicator(length: 6, filledCount: 0),
            const SizedBox(height: 12),
            const PinDotIndicator(length: 6, filledCount: 3),
            const SizedBox(height: 12),
            const PinDotIndicator(length: 6, filledCount: 6),
            const SizedBox(height: 24),
            const SectionHeader(title: 'PinNumberPad'),
            const SizedBox(height: 10),
            const Center(
              child: SizedBox(
                width: 252,
                child: PinNumberPad(
                  onDigit: _noopDigit,
                  onBackspace: _noop,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Chain icons (same SVG assets + treatment as AccountDetail) ─
            const SectionHeader(title: 'Chain icons'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _ChainIconLabel(chain: 'ethereum', label: 'ETH'),
                _ChainIconLabel(chain: 'solana', label: 'SOL'),
                _ChainIconLabel(chain: 'bitcoin', label: 'BTC'),
                _ChainIconLabel(chain: 'tron', label: 'TRON'),
                _ChainIconLabel(chain: 'sui', label: 'SUI'),
              ],
            ),
            const SizedBox(height: 28),

            // ── Warning ──────────────────────────────────────────────
            const SectionHeader(title: 'WarningBanner'),
            const SizedBox(height: 10),
            const WarningBanner(
              message: '任何人不会向你索要助记词。切勿截屏或分享给任何人。',
            ),
            const SizedBox(height: 28),

            // ── Neobrutalist chrome (light only) ─────────────────────
            //
            // The neo primitives only paint in light mode — in dark NeoCard
            // falls back to the legacy chrome and NeoButton is not meant to be
            // built at all — so the whole block is gated on the token.
            if (c.neobrutalism) ...[
              const SectionHeader(title: 'NeoCard / NeoButton / NeoCodeBlock'),
              const SizedBox(height: 10),
              NeoCard(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'NeoCard — 2px 黑描边 · 6px 圆角 · 零模糊 4px 偏移阴影',
                  style: TextStyle(color: c.text, fontSize: 13),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: NeoButton(
                      label: 'Brand',
                      icon: Icons.add,
                      expanded: true,
                      onTap: _noop,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: NeoButton(
                      label: 'Quiet',
                      quiet: true,
                      expanded: true,
                      onTap: _noop,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              NeoCodeBlock(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Account number chip (the real AccountRow) ──────────
              const SectionHeader(title: 'AccountRow · 序号方块'),
              const SizedBox(height: 10),
              NeoCard(
                clip: true,
                child: Column(
                  children: [
                    AccountRow(account: ethAccount, onTap: _noop, onCopy: _noop),
                    AccountRow(
                      account: solAccount2,
                      onTap: _noop,
                      onCopy: _noop,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void _noop() {}
  static void _noopDigit(int digit) {}
}

class _ChainIconLabel extends StatelessWidget {
  final String chain;
  final String label;

  const _ChainIconLabel({required this.chain, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SvgPicture.asset(
            chainIconAssetPath(chain),
            width: 22,
            height: 22,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: c.text.withAlpha(140),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
