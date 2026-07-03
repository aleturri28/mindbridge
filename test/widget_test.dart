import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/app.dart';
import 'package:mindbridge/core/providers.dart';
import 'package:mindbridge/data/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('la home mostra saluto e avvio sessione', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final Preferences prefs = await Preferences.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const MindBridgeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ciao!'), findsOneWidget);
    expect(find.text('AVVIA SESSIONE DI STUDIO'), findsOneWidget);
    expect(find.text('Diario emotivo'), findsOneWidget);
    expect(find.text('Impostazioni'), findsOneWidget);
  });
}
