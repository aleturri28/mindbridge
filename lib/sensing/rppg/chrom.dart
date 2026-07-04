import 'dart:math' as math;

import 'rppg_config.dart';

/// Campione RGB con timestamp, ingresso del CHROM.
class ChromSample {
  const ChromSample({
    required this.r,
    required this.g,
    required this.b,
    required this.timestampMs,
  });

  final double r;
  final double g;
  final double b;
  final int timestampMs;
}

/// Uscita del CHROM su una finestra: bpm stimato + purezza spettrale 0..1.
class ChromResult {
  const ChromResult({required this.hrBpm, required this.quality});

  final double hrBpm;
  final double quality;
}

double _mean(List<double> xs) {
  double sum = 0;
  for (final double x in xs) {
    sum += x;
  }
  return sum / xs.length;
}

double _std(List<double> xs, double mean) {
  double sumSq = 0;
  for (final double x in xs) {
    final double d = x - mean;
    sumSq += d * d;
  }
  return math.sqrt(sumSq / xs.length);
}

/// Stima HR e qualità da una finestra di campioni RGB con l'algoritmo
/// CHROM: normalizzazione per canale, combinazione di crominanza
/// (Xs=3Rn-2Gn, Ys=1.5Rn+Gn-1.5Bn, S=Xs-alpha*Ys), poi ricerca del picco
/// in frequenza ristretta a 0.7-3Hz (la restrizione di banda funge da
/// band-pass, evitando una libreria FFT esterna). Ritorna null se la
/// finestra è troppo corta.
ChromResult? estimateHeartRate(List<ChromSample> samples) {
  if (samples.length < RppgConfig.minSamplesForEstimate) {
    return null;
  }

  final List<double> rs = <double>[for (final ChromSample s in samples) s.r];
  final List<double> gs = <double>[for (final ChromSample s in samples) s.g];
  final List<double> bs = <double>[for (final ChromSample s in samples) s.b];
  final List<double> tSeconds = <double>[
    for (final ChromSample s in samples) s.timestampMs / 1000,
  ];

  final double meanR = _mean(rs);
  final double meanG = _mean(gs);
  final double meanB = _mean(bs);
  if (meanR == 0 || meanG == 0 || meanB == 0) {
    return const ChromResult(hrBpm: 0, quality: 0);
  }

  final int n = samples.length;
  final List<double> xs = List<double>.generate(
      n, (int i) => 3 * (rs[i] / meanR) - 2 * (gs[i] / meanG));
  final List<double> ys = List<double>.generate(
      n,
      (int i) =>
          1.5 * (rs[i] / meanR) + (gs[i] / meanG) - 1.5 * (bs[i] / meanB));

  final double xsMean = _mean(xs);
  final double ysMean = _mean(ys);
  final double stdXs = _std(xs, xsMean);
  final double stdYs = _std(ys, ysMean);
  final double alpha = stdYs == 0 ? 0 : stdXs / stdYs;

  final List<double> combined = List<double>.generate(
      n, (int i) => (xs[i] - xsMean) - alpha * (ys[i] - ysMean));

  double bestFreq = RppgConfig.bandLowHz;
  double bestPower = -1;
  double totalPower = 0;
  final int steps =
      ((RppgConfig.bandHighHz - RppgConfig.bandLowHz) / RppgConfig.frequencyStepHz)
          .round();
  for (int step = 0; step <= steps; step++) {
    final double freq = RppgConfig.bandLowHz + step * RppgConfig.frequencyStepHz;
    double re = 0, im = 0;
    for (int i = 0; i < n; i++) {
      final double angle = -2 * math.pi * freq * tSeconds[i];
      re += combined[i] * math.cos(angle);
      im += combined[i] * math.sin(angle);
    }
    final double power = re * re + im * im;
    totalPower += power;
    if (power > bestPower) {
      bestPower = power;
      bestFreq = freq;
    }
  }

  final double quality = totalPower == 0 ? 0 : bestPower / totalPower;
  return ChromResult(hrBpm: bestFreq * 60, quality: quality);
}
