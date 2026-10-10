import 'package:flutter/material.dart';

import 'package:open_ledger_app/ui/theme/color_tokens.dart';

import '../gallery_catalog.dart';

class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          children: [
            Text(
              'DESIGN GALLERY',
              style: TextStyle(
                color: c.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Open Ledger App',
              style: TextStyle(
                color: c.text,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '这里渲染的就是将上线的 Flutter 组件与屏幕，使用固定假数据，'
              '编译为 Chrome 单一目标（评审/截图/迭代），'
              '无 Web → Flutter 翻译损耗（ADR-005）。',
              style: TextStyle(
                color: c.text.withAlpha(150),
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            for (final group in galleryGroups) ...[
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  group.label.toUpperCase(),
                  style: TextStyle(
                    color: c.text.withAlpha(100),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              for (final item in group.items)
                _CatalogCard(item: item),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  final GalleryItem item;

  const _CatalogCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: () => item.open(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Icon(item.icon, size: 19, color: c.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text.withAlpha(120),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chevron_right, color: c.text.withAlpha(90)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
