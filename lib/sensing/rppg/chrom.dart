import 'rppg_config.dart';
import 'spectral.dart';

/// Campione RGB con timestamp, ingresso comune di CHROM e POS.
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

/// Uscita di una stima su una finestra: bpm stimato + purezza spettrale 0..1.
class ChromResult {
  const ChromResult({required this.hrBpm, required this.quality});

  final double hrBpm;
  final double quality;
}

/// Stima HR e qualità da una finestra di campioni RGB con l'algoritmo
/// CHROM: normalizzazione per canale, combinazione di crominanza
/// (Xs=3Rn-2Gn, Ys=1.5Rn+Gn-1.5Bn, S=Xs-alpha*Ys), poi ricerca del picco
/// in banda (vedi [scanInBand]). Ritorna null se la finestra è troppo corta
/// o il segnale è degenere. Mantenuto come alternativa testata a [estimateHeartRatePos]
/// (POS è l'algoritmo attivo — CLAUDE.md: «CHROM, in alternativa POS»).
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

  final double meanR = mean(rs);
  final double meanG = mean(gs);
  final double meanB = mean(bs);
  if (meanR == 0 || meanG == 0 || meanB == 0) {
    // Segnale degenere (canale a media nulla): nessuna stima, coerente con
    // gli altri percorsi «nessun segnale» che ritornano null (mai un bpm
    // fabbricato — NFR3).
    return null;
  }

  final int n = samples.length;
  final List<double> xs = List<double>.generate(
      n, (int i) => 3 * (rs[i] / meanR) - 2 * (gs[i] / meanG));
  final List<double> ys = List<double>.generate(
      n,
      (int i) =>
          1.5 * (rs[i] / meanR) + (gs[i] / meanG) - 1.5 * (bs[i] / meanB));

  final double xsMean = mean(xs);
  final double ysMean = mean(ys);
  final double stdXs = std(xs, xsMean);
  final double stdYs = std(ys, ysMean);
  final double alpha = stdYs == 0 ? 0 : stdXs / stdYs;

  final List<double> combined = List<double>.generate(
      n, (int i) => (xs[i] - xsMean) - alpha * (ys[i] - ysMean));

  return scanInBand(combined, tSeconds);
}
