import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/theme/app_theme.dart';

import 'gallery_boot.dart';
import 'gallery_controller.dart';
import 'gallery_router.dart';

class GalleryApp extends StatefulWidget {
  final GalleryBoot boot;

  const GalleryApp({super.key, required this.boot});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final GalleryController _controller;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _controller = GalleryController(
      themeMode:
          widget.boot.theme == 'light' ? ThemeMode.light : ThemeMode.dark,
      locale: Locale(widget.boot.lang),
    );
    _router = createGalleryRouter(widget.boot);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GalleryScope(
      controller: _controller,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return MaterialApp.router(
            title: 'Open Ledger App Gallery',
            debugShowCheckedModeBanner: false,
            themeMode: _controller.themeMode,
            // Pin the platform to Android regardless of the host OS: the
            // gallery runs in Chrome/Linux (and headless Chrome for shots),
            // where Flutter otherwise reports the browser's OS. Without this,
            // platform-dependent defaults diverge from the shipped app —
            // e.g. iOS/macOS centers AppBar titles, Android left-aligns them.
            theme: lightTheme.copyWith(platform: TargetPlatform.android),
            darkTheme: darkTheme.copyWith(platform: TargetPlatform.android),
            locale: _controller.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: _router,
            // Flutter web quirk: Text widgets without an explicit decoration
            // inherit the browser's default underline. Override globally so
            // the gallery renders like the Android target.
            builder: (context, child) => DefaultTextStyle(
              style: const TextStyle(decoration: TextDecoration.none),
              child: child!,
            ),
          );
        },
      ),
    );
  }
}
