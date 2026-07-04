import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/chrom.dart';
import 'package:mindbridge/sensing/rppg/rppg_config.dart';

/// Genera una finestra sintetica di campioni RGB con una modulazione
/// sinusoidale a [freqHz] sovrapposta a un colore pelle plausibile,
/// coerente con le proporzioni di crominanza usate dal CHROM (R più
/// modulato di G, G più di B — come il segnale di volume ematico reale).
List<ChromSample> syntheticPulse({
  required double freqHz,
  double amplitude = 2.0,
  double noiseAmplitude = 0,
  int sampleCount = 300,
  double fps = 30,
  math.Random? random,
}) {
  final math.Random rnd = random ?? math.Random(42);
  return <ChromSample>[
    for (int i = 0; i < sampleCount; i++)
      () {
        final double t = i / fps;
        final double pulse = math.sin(2 * math.pi * freqHz * t);
        final double noise =
            noiseAmplitude == 0 ? 0 : (rnd.nextDouble() * 2 - 1) * noiseAmplitude;
        return ChromSample(
          r: 128 + amplitude * pulse + noise,
          g: 128 + 0.6 * amplitude * pulse + noise,
          b: 128 + 0.3 * amplitude * pulse + noise,
          timestampMs: (t * 1000).round(),
        );
      }(),
  ];
}

void main() {
  group('estimateHeartRate', () {
    test('clean 1.2 Hz pulse resolves to ~72 bpm with high quality', () {
      final ChromResult? result =
          estimateHeartRate(syntheticPulse(freqHz: 1.2));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(72, 100));
      expect(result.quality, greaterThan(0.1));
    });

    test('clean 2.0 Hz pulse resolves to ~120 bpm', () {
      final ChromResult? result =
          estimateHeartRate(syntheticPulse(freqHz: 2.0));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(120, 100));
    });

    test('pure noise (no pulse) yields low quality', () {
      final ChromResult? result = estimateHeartRate(syntheticPulse(
        freqHz: 1.2,
        amplitude: 0,
        noiseAmplitude: 3,
      ));
      expect(result, isNotNull);
      expect(result!.quality, lessThan(RppgConfig.qualityThreshold));
    });

    test('too few samples returns null', () {
      final ChromResult? result = estimateHeartRate(syntheticPulse(
        freqHz: 1.2,
        sampleCount: RppgConfig.minSamplesForEstimate - 1,
      ));
      expect(result, isNull);
    });
  });
}
