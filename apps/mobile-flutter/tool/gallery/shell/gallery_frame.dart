import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../gallery_boot.dart';
import '../gallery_catalog.dart';
import '../gallery_controller.dart';

/// Gallery chrome: a fixed 390×844 phone canvas with a catalog navigation
/// rail beside it. `chrome=0` renders the phone canvas alone for deterministic
/// screenshots.
class GalleryFrame extends StatelessWidget {
  static const double phoneWidth = 390;
  static const double phoneHeight = 844;

  final GalleryBoot boot;
  final GoRouterState state;
  final Widget child;

  const GalleryFrame({
    super.key,
    required this.boot,
    required this.state,
    required this.child,
  });

  bool _isActive(GalleryItem item) {
    if (state.matchedLocation != item.routePath) return false;
    final currentChain = state.uri.queryParameters['chain'];
    if (item.chain != null && item.chain != currentChain) return false;
    // Main-screen tabs share `/screens/main`, so the `tab` query parameter is
    // what distinguishes the active entry.
    final currentTab = state.uri.queryParameters['tab'];
    return (item.tab ?? '') == (currentTab ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final phone = ClipRRect(
      borderRadius: BorderRadius.circular(44),
      child: SizedBox(
        width: phoneWidth,
        height: phoneHeight,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: child,
        ),
      ),
    );

    if (boot.chromeDisabled) {
      // Raw, full-bleed product screen — golden comparisons and L1 review
      // must measure the shipped widget without bezel or rounded corners.
      return SizedBox(width: phoneWidth, height: phoneHeight, child: child);
    }

    return Material(
      color: const Color(0xFF161616),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GalleryNav(
            state: state,
            isActive: _isActive,
          ),
          const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(56),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 48,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: phone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryNav extends StatelessWidget {
  final GoRouterState state;
  final bool Function(GalleryItem) isActive;

  const _GalleryNav({required this.state, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final controller = GalleryController.of(context);
    final onHome = state.matchedLocation == '/';

    return SizedBox(
      width: 264,
      // Material (not ColoredBox) provides DefaultTextStyle for the section
      // headers and title; without it they get the yellow fallback underlines.
      child: Material(
        color: const Color(0xFF101010),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFA1F44E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'OPEN LEDGER APP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Design Gallery',
                      style: TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children: [
                    _NavTile(
                      label: 'Catalog',
                      icon: Icons.home_outlined,
                      active: onHome,
                      onTap: () => context.go('/'),
                    ),
                    const SizedBox(height: 12),
                    for (final group in galleryGroups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                        child: Text(
                          group.label.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0x66FFFFFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      for (final item in group.items)
                        _NavTile(
                          label: item.title,
                          icon: item.icon,
                          active: isActive(item),
                          onTap: () => item.open(context),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              _ControlPanel(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _NavTile({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? const Color(0xFF1F2A12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: active
                      ? const Color(0xFFA1F44E)
                      : const Color(0xAAFFFFFF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? Colors.white
                          : const Color(0xAAFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final GalleryController controller;

  const _ControlPanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SegmentButton(
                label: 'Dark',
                selected: controller.isDark,
                onTap: () => controller.setThemeMode(ThemeMode.dark),
              ),
              const SizedBox(width: 6),
              _SegmentButton(
                label: 'Light',
                selected: !controller.isDark,
                onTap: () => controller.setThemeMode(ThemeMode.light),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final (code, label) in const [
                ('en', 'EN'),
                ('zh', '中'),
                ('ja', '日'),
                ('ko', '한'),
              ])
                _SegmentButton(
                  label: label,
                  compact: true,
                  selected: controller.locale.languageCode == code,
                  onTap: () => controller.setLocale(Locale(code)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '截图 URL 追加 ?chrome=0',
            style: TextStyle(color: Color(0x55FFFFFF), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFA1F44E) : const Color(0xFF222222),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 18,
            vertical: 7,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.black : const Color(0xAAFFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}
