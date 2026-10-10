import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../services/settings_service.dart';
import '../../theme/color_tokens.dart';
import '../../theme/widgets/brand_mark.dart';
import '../../widgets/common/enigma_logo_icon.dart';
import 'components/entry_card.dart';

/// Welcome screen — the app's landing page with three wallet entry points.
///
/// Ported from the original TypeScript implementation.
/// Displays the OpenLedger mark, app title, subtitle, and three action cards:
/// Create New Wallet, Import Existing, Enigma Setup.
///
/// Also hosts a language selector so users can switch the display language
/// before creating a wallet (the Settings screen is only reachable once a
/// wallet exists). When [settingsService] is null the selector still renders
/// but is inert — used by previews that mount the screen without services.
class WelcomeScreen extends StatelessWidget {
  final SettingsService? settingsService;

  const WelcomeScreen({super.key, this.settingsService});

  /// Localized display name of the currently active locale.
  String _currentLanguageName(AppLocalizations l10n, Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return l10n.languageEnglish;
      case 'zh':
        return l10n.languageChinese;
      case 'ja':
        return l10n.languageJapanese;
      case 'ko':
        return l10n.languageKorean;
      default:
        return l10n.languageEnglish;
    }
  }

  /// Shows the language picker sheet: English / 中文 / 日本語 / 한국어.
  void _showLanguagePicker(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.dark
        : ColorTokens.light;
    final current = settingsService?.locale ?? const Locale('en');

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.text.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  l10n.language,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final (locale, label) in [
                (const Locale('en'), l10n.languageEnglish),
                (const Locale('zh'), l10n.languageChinese),
                (const Locale('ja'), l10n.languageJapanese),
                (const Locale('ko'), l10n.languageKorean),
              ])
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    settingsService?.setLocale(locale);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        if (current.languageCode == locale.languageCode)
                          Icon(Icons.check_rounded,
                              color: c.primary, size: 22),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorTokens.dark : ColorTokens.light;
    final currentLocale = settingsService?.locale ?? const Locale('en');

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final topPadding = constraints.maxHeight * 0.12;

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: topPadding),
                      child: Column(
                        children: [
                          // ── Brand Mark ───────────────────────────────
                          const BrandMark(size: 120),

                          const SizedBox(height: 32),

                          // ── App Title ─────────────────────────────────
                          Text(
                            l10n.appTitle,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),

                          const SizedBox(height: 10),

                          // ── Subtitle ──────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Text(
                              l10n.welcomeSubtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: c.text.withAlpha(180),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),

                          const SizedBox(height: 48),

                          // ── Action Cards ──────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                EntryCard(
                                  key: const Key('entry-create'),
                                  icon: Icons.add_circle_outline,
                                  title: l10n.createWallet,
                                  description: l10n.generateWithTouch,
                                  onTap: () => context.go('/entropy'),
                                ),
                                const SizedBox(height: 12),
                                EntryCard(
                                  key: const Key('entry-import'),
                                  icon: Icons.download,
                                  title: l10n.importWallet,
                                  description: l10n.restoreFromSeed,
                                  onTap: () => context.go('/import'),
                                ),
                                const SizedBox(height: 12),
                                EntryCard(
                                  key: const Key('entry-enigma'),
                                  iconBuilder: (color) =>
                                      EnigmaLogoIcon(color: color),
                                  title: l10n.enigmaWallet,
                                  description: l10n.advancedEnigma,
                                  onTap: () => context.go('/enigma'),
                                ),
                              ],
                            ),
                          ),

                          // Bottom spacer so content isn't jammed at bottom
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── Language selector (top-right) ─────────────────────────
            Positioned(
              top: 8,
              right: 16,
              child: InkWell(
                key: const Key('language-selector'),
                borderRadius: BorderRadius.circular(R.xl),
                onTap: () => _showLanguagePicker(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(R.xl),
                    border: Border.all(color: c.border.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.language, size: 16, color: c.text.withAlpha(200)),
                      const SizedBox(width: 6),
                      Text(
                        _currentLanguageName(l10n, currentLocale),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
