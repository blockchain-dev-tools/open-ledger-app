import 'package:flutter/material.dart';

import 'color_tokens.dart';

/// Builds a [ThemeData] from [ColorTokens] for a given [Brightness].
ThemeData _buildTheme(ColorTokens c, Brightness b) {
  // Flutter web quirk: Text widgets without explicit decoration inherit the
  // browser's default underline. Ensure every text style in the theme has
  // decoration: TextDecoration.none so web renders like Android.
  final baseTextStyle = TextStyle(decoration: TextDecoration.none);
  final textTheme = TextTheme(
    displayLarge: baseTextStyle.copyWith(fontSize: 57, fontWeight: FontWeight.w400),
    displayMedium: baseTextStyle.copyWith(fontSize: 45, fontWeight: FontWeight.w400),
    displaySmall: baseTextStyle.copyWith(fontSize: 36, fontWeight: FontWeight.w400),
    headlineLarge: baseTextStyle.copyWith(fontSize: 32, fontWeight: FontWeight.w400),
    headlineMedium: baseTextStyle.copyWith(fontSize: 28, fontWeight: FontWeight.w400),
    headlineSmall: baseTextStyle.copyWith(fontSize: 24, fontWeight: FontWeight.w400),
    titleLarge: baseTextStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w500),
    titleMedium: baseTextStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
    titleSmall: baseTextStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    bodyLarge: baseTextStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: baseTextStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: baseTextStyle.copyWith(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: baseTextStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: baseTextStyle.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
    labelSmall: baseTextStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
  );

  return ThemeData(
    useMaterial3: true,
    // Subsetted Noto Sans CJK only covers glyphs missing from engine
    // Roboto — Latin metrics stay identical across web/desktop/Android.
    fontFamilyFallback: const ['NotoSansCJK'],
    brightness: b,
    textTheme: textTheme,
    colorScheme: ColorScheme(
      brightness: b,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.primary,
      onSecondary: c.onPrimary,
      error: c.error,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.text,
      outline: c.border,
      surfaceContainerHighest: c.surface,
    ),
    scaffoldBackgroundColor: c.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: Colors.black26,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
        ),
      ),
    ),
  );
}

/// Dark theme used by [MaterialApp.darkTheme].
final ThemeData darkTheme = _buildTheme(ColorTokens.dark, Brightness.dark);

/// Light theme used by [MaterialApp.theme].
final ThemeData lightTheme = _buildTheme(ColorTokens.light, Brightness.light);
