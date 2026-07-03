import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/core/theme/app_theme.dart';
import 'package:mindbridge/features/session/widgets/stress_alert_sheet.dart';
import 'package:mindbridge/l10n/gen/app_localizations.dart';

Widget host(void Function(StressAlertChoice) onChoice) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('it'),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: () async =>
              onChoice(await StressAlertSheet.show(context)),
          child: const Text('apri'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('il bottom sheet propone le tre scelte FR4', (
    WidgetTester tester,
  ) async {
    StressAlertChoice? choice;
    await tester.pumpWidget(host((StressAlertChoice c) => choice = c));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    expect(find.text('Potresti beneficiare di una pausa'), findsOneWidget);
    expect(find.text('PAUSA GUIDATA'), findsOneWidget);
    expect(find.text('Posticipa 20 min'), findsOneWidget);
    expect(find.text('Ignora'), findsOneWidget);

    // 1° tap: dal foglio si va dritti alla scelta pausa (2 tap totali
    // per avviare la pausa, vincolo di frizione minima).
    await tester.tap(find.text('PAUSA GUIDATA'));
    await tester.pumpAndSettle();
    expect(choice, StressAlertChoice.pause);
  });

  testWidgets('chiudere il foglio senza scegliere equivale a Ignora', (
    WidgetTester tester,
  ) async {
    StressAlertChoice? choice;
    await tester.pumpWidget(host((StressAlertChoice c) => choice = c));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    // Tap fuori dal foglio.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(choice, StressAlertChoice.ignore);
  });
}
