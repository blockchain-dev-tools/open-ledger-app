/// Widget tests for [PrivacyShield] — the secret-display envelope's cover and
/// screenshot flag (ADR-011 §6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/interfaces/screen_security.dart';
import 'package:open_ledger_app/generated/l10n/app_localizations.dart';
import 'package:open_ledger_app/ui/widgets/security/privacy_shield.dart';

/// Counts the flag toggles without touching a platform channel.
class _RecordingScreenSecurity implements IScreenSecurity {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enable() async => enableCalls++;

  @override
  Future<void> disable() async => disableCalls++;
}

Widget _wrap(Widget child) => MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

void main() {
  testWidgets('holds the screenshot flag while mounted', (tester) async {
    final security = _RecordingScreenSecurity();

    await tester.pumpWidget(
      _wrap(
        PrivacyShield(
          screenSecurity: security,
          child: const Text('secret'),
        ),
      ),
    );
    expect(security.enableCalls, 1);
    expect(security.disableCalls, 0);

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    expect(security.disableCalls, 1);
  });

  testWidgets('covers the child on losing focus and restores it after',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PrivacyShield(child: Text('secret'))),
    );
    expect(find.text('secret'), findsOneWidget);
    expect(find.text('Content hidden'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Content hidden'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Content hidden'), findsNothing);
    expect(find.text('secret'), findsOneWidget);
  });

  testWidgets('previewHidden freezes the covered state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PrivacyShield(previewHidden: true, child: Text('secret')),
      ),
    );

    expect(find.text('Content hidden'), findsOneWidget);
  });
}
