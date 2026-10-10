import 'package:flutter/material.dart';

/// Interactive gallery controls (theme / locale). Initial state comes from
/// [GalleryBoot] URL parameters; toggling here updates the live app without a
/// reload, while a fresh page load with `?theme=&lang=` stays deterministic for
/// screenshots.
class GalleryController extends ChangeNotifier {
  ThemeMode themeMode;
  Locale locale;

  GalleryController({required this.themeMode, required this.locale});

  bool get isDark => themeMode == ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
  }

  void toggleTheme() {
    setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  void setLocale(Locale next) {
    if (locale == next) return;
    locale = next;
    notifyListeners();
  }

  static GalleryController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GalleryScope>();
    assert(scope != null, 'GalleryController not found in widget tree');
    return scope!.notifier!;
  }
}

class GalleryScope extends InheritedNotifier<GalleryController> {
  const GalleryScope({
    super.key,
    required GalleryController controller,
    required super.child,
  }) : super(notifier: controller);
}
