import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/rppg_isolate.dart';

void main() {
  test('RppgProcessor spawns, ingests synthetic frames, emits an estimate',
      () async {
    final RppgProcessor processor = await RppgProcessor.spawn();
    addTearDown(processor.dispose);

    final Future<RppgEstimate> firstEstimate = processor.estimates.first;

    const double fps = 30;
    for (int i = 0; i < 300; i++) {
      final int tMs = (i / fps * 1000).round();
      final double t = tMs / 1000;
      const double w = 2 * math.pi * 1.2;
      // Sfasamento per canale: una singola sinusoide in fase su R/G/B si
      // annulla sotto CHROM (Xs e Ys proporzionali). Lo sfasamento rende il
      // polso recuperabile — coerente con i fixture di Task 2/3.
      processor.addFrame(
        r: 128 + 2 * math.sin(w * t),
        g: 128 + 1.2 * math.sin(w * t - 0.6),
        b: 128 + 0.6 * math.sin(w * t - 1.2),
        timestampMs: tMs,
      );
    }

    final RppgEstimate estimate =
        await firstEstimate.timeout(const Duration(seconds: 5));
    expect(estimate.hrBpm, closeTo(72, 6));
  });
}
