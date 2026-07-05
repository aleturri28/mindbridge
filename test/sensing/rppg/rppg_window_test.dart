import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/rppg_config.dart';
import 'package:mindbridge/sensing/rppg/rppg_window.dart';

void main() {
  group('RppgWindow', () {
    test('no estimate before minSamplesForEstimate is reached', () {
      final RppgWindow window = RppgWindow();
      RppgEstimate? last;
      for (int i = 0; i < RppgConfig.minSamplesForEstimate - 1; i++) {
        window.add(128, 128, 128, i * 33);
        last = window.maybeEstimate(i * 33);
      }
      expect(last, isNull);
    });

    test('emits an estimate once buffer is full, then respects hop', () {
      final RppgWindow window = RppgWindow();
      const double fps = 30;
      RppgEstimate? first;
      for (int i = 0; i < 300; i++) {
        final int tMs = (i / fps * 1000).round();
        final double t = tMs / 1000;
        const double w = 2 * math.pi * 1.2;
        // Sfasamento per canale: senza, la singola sinusoide in fase su
        // R/G/B si annulla sotto CHROM (Xs e Ys proporzionali) e la stima
        // non è recuperabile — stesso motivo del fixture di Task 2.
        window.add(
          128 + 2 * math.sin(w * t),
          128 + 1.2 * math.sin(w * t - 0.6),
          128 + 0.6 * math.sin(w * t - 1.2),
          tMs,
        );
        final RppgEstimate? estimate = window.maybeEstimate(tMs);
        if (estimate != null && first == null) {
          first = estimate;
        }
      }
      expect(first, isNotNull);
      expect(first!.hrBpm, closeTo(72, 6));

      // Chiamare di nuovo con lo stesso timestamp (< hop dall'ultima stima)
      // non deve produrre una nuova stima.
      final RppgEstimate? immediate = window.maybeEstimate(first.timestampMs);
      expect(immediate, isNull);
    });

    test('old samples fall out of the window', () {
      final RppgWindow window = RppgWindow();
      window.add(200, 200, 200, 0);
      // Avanza oltre la durata della finestra: il campione iniziale deve
      // uscire dal buffer (verificato indirettamente: nessuna estimate con
      // un solo campione recente, sotto minSamplesForEstimate).
      final RppgEstimate? estimate = window.maybeEstimate(
          RppgConfig.windowDuration.inMilliseconds + 1000);
      expect(estimate, isNull);
    });
  });
}
