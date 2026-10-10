import 'package:flutter/foundation.dart';

/// Values parsed once from the launch URL before the first frame.
///
/// Supported query parameters (after the hash route, e.g.
/// `/#/account/0?chain=eth&theme=dark&lang=zh&chrome=0`):
/// - `chain=eth|sol|btc|tron|sui` — selects mock data for screen scenarios
/// - `tab=0|1|2|3`                — initial Main-screen tab (Accounts/BLE/
///                                  History/Settings)
/// - `theme=dark|light`          — initial theme (default dark)
/// - `lang=en|zh|ja|ko`          — initial locale (default en)
/// - `chrome=0`                  — phone viewport only, no bezel/catalog
///                                 (used by the headless screenshot pipeline)
///
/// On non-web targets [Uri.base] has no URL fragment, so launches outside the
/// browser fall back to the catalog home.
class GalleryBoot {
  final String initialLocation;
  final Map<String, String> query;
  final bool chromeDisabled;
  final String theme;
  final String lang;

  const GalleryBoot({
    required this.initialLocation,
    required this.query,
    required this.chromeDisabled,
    required this.theme,
    required this.lang,
  });

  factory GalleryBoot.current() {
    Uri? deep;
    if (kIsWeb) {
      final fragment = Uri.base.fragment;
      if (fragment.startsWith('/')) {
        deep = Uri.tryParse(fragment);
      }
    }

    final location = deep?.path ?? '/';
    final query = Map<String, String>.from(deep?.queryParameters ?? const {});
    final lang = const {'en', 'zh', 'ja', 'ko'}.contains(query['lang'])
        ? query['lang']!
        : 'en';

    return GalleryBoot(
      initialLocation: location,
      query: query,
      chromeDisabled: query['chrome'] == '0',
      theme: query['theme'] == 'light' ? 'light' : 'dark',
      lang: lang,
    );
  }
}
