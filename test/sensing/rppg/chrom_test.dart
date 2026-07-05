import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/chrom.dart';
import 'package:mindbridge/sensing/rppg/rppg_config.dart';

/// Genera una finestra sintetica di campioni RGB con una modulazione
/// sinusoidale a [freqHz] sovrapposta a un colore pelle plausibile.
///
/// Le ampiezze per canale decrescono R>G>B (come il volume ematico reale),
/// ma soprattutto ogni canale ha uno sfasamento diverso ([phaseG], [phaseB]):
/// senza questo il segnale sarebbe una singola sinusoide identica su tutti i
/// canali, che la combinazione di crominanza del CHROM (Xs-alpha*Ys) annulla
/// per costruzione (alpha=std(Xs)/std(Ys)). Lo sfasamento — fisicamente reale,
/// il fronte d'onda del polso raggiunge i canali con timing diverso — rende
/// Xs e Ys non proporzionali, così la fondamentale sopravvive ed è
/// recuperabile. Il rumore, se presente, è indipendente per canale.
List<ChromSample> syntheticPulse({
  required double freqHz,
  double amplitude = 2.0,
  double noiseAmplitude = 0,
  int sampleCount = 300,
  double fps = 30,
  double phaseG = 0.6,
  double phaseB = 1.2,
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
        return ChromSample(
          r: 128 + amplitude * math.sin(w * t) + noise(),
          g: 128 + 0.6 * amplitude * math.sin(w * t - phaseG) + noise(),
          b: 128 + 0.3 * amplitude * math.sin(w * t - phaseB) + noise(),
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
      expect(result!.hrBpm, closeTo(72, 5));
      // La griglia di scan (0.05 Hz) è più fitta della risoluzione di
      // Rayleigh della finestra (1/10s = 0.1 Hz): la potenza di un tono puro
      // si distribuisce inevitabilmente sui bin adiacenti, quindi la purezza
      // spettrale di un segnale pulito satura intorno a 0.5 con questa
      // metrica. L'invariante che conta è che un segnale pulito superi
      // comodamente la soglia di affidabilità dell'app.
      expect(result.quality, greaterThan(RppgConfig.qualityThreshold));
    });

    test('clean 2.0 Hz pulse resolves to ~120 bpm', () {
      final ChromResult? result =
          estimateHeartRate(syntheticPulse(freqHz: 2.0));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(120, 6));
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
