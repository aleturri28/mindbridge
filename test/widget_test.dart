import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/app.dart';

void main() {
  testWidgets('app starts and shows the Phase 0 placeholder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MindBridgeApp()));

    expect(find.text('MindBridge'), findsOneWidget);
    // Semaforo: etichetta testuale sempre presente accanto al colore.
    expect(find.text('Basso'), findsOneWidget);
    expect(find.text('Medio'), findsOneWidget);
    expect(find.text('Alto'), findsOneWidget);
  });
}
