import 'chrom.dart' show ChromResult, ChromSample;
import 'rppg_config.dart';
import 'spectral.dart';

/// Stima HR e qualità da una finestra di campioni RGB con l'algoritmo POS
/// (Plane-Orthogonal-to-Skin, Wang et al. 2017), l'algoritmo attivo della
/// pipeline (CLAUDE.md: «CHROM, in alternativa POS»; POS è più robusto al
/// movimento).
///
/// Passi: normalizzazione temporale per canale (Cn = C/mean(C)), proiezione
/// sul piano ortogonale al tono pelle
///   S1 = Gn − Bn
///   S2 = Gn + Bn − 2·Rn
/// combinazione sintonizzata h = S1 + (std(S1)/std(S2))·S2, rimozione della
/// media, poi ricerca del picco in banda (vedi [scanInBand]).
///
/// Ritorna null se la finestra è troppo corta o un canale è degenere
/// (media nulla) — mai un bpm fabbricato (NFR3).
ChromResult? estimateHeartRatePos(List<ChromSample> samples) {
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
    return null;
  }

  final int n = samples.length;
  final List<double> s1 = List<double>.generate(
      n, (int i) => (gs[i] / meanG) - (bs[i] / meanB));
  final List<double> s2 = List<double>.generate(
      n, (int i) => (gs[i] / meanG) + (bs[i] / meanB) - 2 * (rs[i] / meanR));

  final double s1Mean = mean(s1);
  final double s2Mean = mean(s2);
  final double stdS1 = std(s1, s1Mean);
  final double stdS2 = std(s2, s2Mean);
  final double alpha = stdS2 == 0 ? 0 : stdS1 / stdS2;

  // h = S1 + alpha·S2, con la media rimossa così lo scan vede solo l'AC.
  final List<double> combined = List<double>.generate(
      n, (int i) => (s1[i] - s1Mean) + alpha * (s2[i] - s2Mean));

  return scanInBand(combined, tSeconds);
}
