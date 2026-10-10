import 'package:flutter/material.dart';

import 'package:open_ledger_app/ui/theme/color_tokens.dart';

/// Documents one palette per page: `/tokens/dark` and `/tokens/light` each
/// render a full screen with their own [ColorTokens].
class TokensPage extends StatelessWidget {
  final ColorTokens tokens;
  final String label;

  const TokensPage({super.key, required this.tokens, required this.label});

  const TokensPage.dark({super.key})
      : tokens = ColorTokens.dark,
        label = 'DARK';

  const TokensPage.light({super.key})
      : tokens = ColorTokens.light,
        label = 'LIGHT';

  @override
  Widget build(BuildContext context) {
    return _TokenSection(tokens: tokens, label: label);
  }
}

class _TokenSection extends StatelessWidget {
  final ColorTokens tokens;
  final String label;

  const _TokenSection({required this.tokens, required this.label});

  @override
  Widget build(BuildContext context) {
    final swatches = <_Swatch>[
      _Swatch('primary', tokens.primary, '主操作 / 品牌强调'),
      _Swatch('bg', tokens.bg, '页面底色'),
      _Swatch('surface', tokens.surface, '卡片 / AppBar'),
      _Swatch('text', tokens.text, '主文字'),
      _Swatch('onPrimary', tokens.onPrimary, '主按钮文字'),
      _Swatch('onBg', tokens.onBg, '背景上的内容色'),
      _Swatch('error', tokens.error, '错误 / 销毁性操作'),
      _Swatch('border', tokens.border, '描边 / 分隔'),
    ];

    // Material (not ColoredBox) so text inherits a proper DefaultTextStyle;
    // without it Flutter paints the fallback yellow wavy underlines.
    return Material(
      color: tokens.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          for (final swatch in swatches)
            _SwatchRow(tokens: tokens, swatch: swatch),
          const SizedBox(height: 10),
          Row(
            children: [
              _RadiusSample(name: 'R.sm', value: R.sm, tokens: tokens),
              const SizedBox(width: 18),
              _RadiusSample(name: 'R.lg', value: R.lg, tokens: tokens),
              const SizedBox(width: 18),
              _RadiusSample(name: 'R.xl', value: R.xl, tokens: tokens),
              const Spacer(),
              Text(
                '字阶 / 间距 token\n待设计体系 ADR',
                style: TextStyle(
                  color: tokens.text.withAlpha(110),
                  fontSize: 10.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch {
  final String name;
  final Color color;
  final String usage;

  const _Swatch(this.name, this.color, this.usage);
}

class _SwatchRow extends StatelessWidget {
  final ColorTokens tokens;
  final _Swatch swatch;

  const _SwatchRow({required this.tokens, required this.swatch});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 38,
              decoration: BoxDecoration(
                color: swatch.color,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: tokens.border),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    swatch.name,
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    swatch.usage,
                    style: TextStyle(
                      color: tokens.text.withAlpha(120),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '#${(swatch.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
              style: TextStyle(
                color: tokens.text.withAlpha(150),
                fontSize: 11.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadiusSample extends StatelessWidget {
  final String name;
  final double value;
  final ColorTokens tokens;

  const _RadiusSample({
    required this.name,
    required this.value,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: tokens.primary.withAlpha(40),
            borderRadius: BorderRadius.circular(value),
            border: Border.all(color: tokens.primary, width: 1.5),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: TextStyle(
            color: tokens.text,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value.toStringAsFixed(0),
          style: TextStyle(color: tokens.text.withAlpha(110), fontSize: 10),
        ),
      ],
    );
  }
}
