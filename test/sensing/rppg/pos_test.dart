import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/chrom.dart';
import 'package:mindbridge/sensing/rppg/pos.dart';
import 'package:mindbridge/sensing/rppg/rppg_config.dart';

/// Finestra sintetica RGB con polso a [freqHz], ampiezze per canale
/// decrescenti R>G>B e sfasamento per canale (senza, la sinusoide identica
/// su tutti i canali si annullerebbe nella combinazione). Deriva common-mode
/// e rumore per canale opzionali, come nel fixture di CHROM.
List<ChromSample> syntheticPulse({
  required double freqHz,
  double amplitude = 2.0,
  double noiseAmplitude = 0,
  int sampleCount = 300,
  double fps = 30,
  double phaseG = 0.6,
  double phaseB = 1.2,
  double driftAmplitude = 0,
  double driftHz = 0.15,
  math.Random? random,
}) {
  final math.Random rnd = random ?? math.Random(42);
  double noise() =>
      noiseAmplitude == 0 ? 0 : (rnd.nextDouble() * 2 - 1) * noiseAmplitude;
  return <ChromSample>[
    for (int i = 0; i < sampleCount; i++)
      () {
        final double t = i / fps;
        final double w = 2 * math.pi * freqHz;
        final double drift =
            driftAmplitude * math.sin(2 * math.pi * driftHz * t);
        return ChromSample(
          r: 128 + amplitude * math.sin(w * t) + drift + noise(),
          g: 128 + 0.6 * amplitude * math.sin(w * t - phaseG) + drift + noise(),
          b: 128 + 0.3 * amplitude * math.sin(w * t - phaseB) + drift + noise(),
          timestampMs: (t * 1000).round(),
        );
      }(),
  ];
}

void main() {
  group('estimateHeartRatePos', () {
    test('clean 1.2 Hz pulse resolves to ~72 bpm above threshold', () {
      final ChromResult? result =
          estimateHeartRatePos(syntheticPulse(freqHz: 1.2));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(72, 5));
      expect(result.quality, greaterThan(RppgConfig.qualityThreshold));
    });

    test('clean 2.0 Hz pulse resolves to ~120 bpm', () {
      final ChromResult? result =
          estimateHeartRatePos(syntheticPulse(freqHz: 2.0));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(120, 6));
    });

    test('common-mode drift is rejected by the POS projection', () {
      final ChromResult? result = estimateHeartRatePos(syntheticPulse(
        freqHz: 1.2,
        amplitude: 2,
        driftAmplitude: 6,
        noiseAmplitude: 0.5,
      ));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(72, 6));
      expect(result.quality, greaterThan(RppgConfig.qualityThreshold));
    });

    test('pure noise (no pulse) yields low quality', () {
      final ChromResult? result = estimateHeartRatePos(syntheticPulse(
        freqHz: 1.2,
        amplitude: 0,
        noiseAmplitude: 3,
      ));
      expect(result, isNotNull);
      expect(result!.quality, lessThan(RppgConfig.qualityThreshold));
    });

    test('too few samples returns null', () {
      final ChromResult? result = estimateHeartRatePos(syntheticPulse(
        freqHz: 1.2,
        sampleCount: RppgConfig.minSamplesForEstimate - 1,
      ));
      expect(result, isNull);
    });
  });
}
