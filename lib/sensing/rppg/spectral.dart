import 'dart:math' as math;

import 'chrom.dart' show ChromResult;
import 'rppg_config.dart';

/// Media aritmetica di [xs] (assume [xs] non vuota).
double mean(List<double> xs) {
  double sum = 0;
  for (final double x in xs) {
    sum += x;
  }
  return sum / xs.length;
}

/// Deviazione standard di [xs] data la sua [avg].
double std(List<double> xs, double avg) {
  double sumSq = 0;
  for (final double x in xs) {
    final double d = x - avg;
    sumSq += d * d;
  }
  return math.sqrt(sumSq / xs.length);
}

/// Cerca il picco cardiaco nel segnale di crominanza [combined] (già privo
/// di media) campionato agli istanti [tSeconds], restringendo la scansione
/// alla banda [RppgConfig.bandLowHz]–[RppgConfig.bandHighHz]. La restrizione
/// di banda funge da band-pass (niente FFT esterna). Ritorna bpm e purezza
/// spettrale (potenza del picco / potenza totale in banda), condivisa da
/// CHROM e POS.
ChromResult scanInBand(List<double> combined, List<double> tSeconds) {
  final int n = combined.length;
  double bestFreq = RppgConfig.bandLowHz;
  double bestPower = -1;
  double totalPower = 0;
  final int steps = ((RppgConfig.bandHighHz - RppgConfig.bandLowHz) /
          RppgConfig.frequencyStepHz)
      .round();
  for (int step = 0; step <= steps; step++) {
    final double freq =
        RppgConfig.bandLowHz + step * RppgConfig.frequencyStepHz;
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
