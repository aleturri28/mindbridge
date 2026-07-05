// lib/sensing/rppg/rppg_config.dart

/// Costanti della pipeline rPPG (CHROM). Centralizzate qui — CLAUDE.md:
/// pesi/soglie in configurazione, non hardcoded sparsi.
abstract final class RppgConfig {
  /// Indici FaceMesh (478 punti, stesso schema di [FrameAnalysis.faceLandmarks])
  /// delle patch di pelle usate per la media RGB. Punto di partenza da
  /// letteratura rPPG; raffinato visivamente (overlay poligono su debug
  /// screen) durante la validazione manuale — stesso approccio empirico già
  /// usato per le costanti di `postureScoreFromPose` in Fase 2.
  static const List<int> foreheadIndices = <int>[10, 108, 151, 337];
  static const List<int> leftCheekIndices = <int>[205, 50, 118, 101];
  static const List<int> rightCheekIndices = <int>[425, 280, 347, 330];

  /// Finestra scorrevole e hop (CLAUDE.md: ~10s finestra, hop 1s).
  static const Duration windowDuration = Duration(seconds: 10);
  static const Duration hopDuration = Duration(seconds: 1);

  /// Banda passante HR: 0.7–3 Hz (42–180 bpm). La ricerca del picco è
  /// ristretta a questa banda, il che funge anche da band-pass.
  static const double bandLowHz = 0.7;
  static const double bandHighHz = 3.0;

  /// Risoluzione della scansione in frequenza (Hz).
  static const double frequencyStepHz = 0.05;

  /// Sotto questa purezza spettrale (potenza del picco / potenza totale in
  /// banda) l'HR non è affidabile: mai mostrarlo come numero (NFR3/NFR10).
  static const double qualityThreshold = 0.35;

  /// Campioni minimi in finestra prima di tentare una stima.
  static const int minSamplesForEstimate = 30;

  /// Oltre questa durata senza una nuova stima HR (o senza volto rilevato),
  /// il segnale è considerato stale: quality forzata a 0 e hr mai mostrato
  /// come numero (mai fabbricare un valore — NFR3/NFR10). 5s equivalgono a
  /// 5 hop mancati, ben oltre qualsiasi cadenza sana, ma abbastanza breve da
  /// degradare onestamente in tempi rapidi.
  static const Duration estimateStaleAfter = Duration(seconds: 5);
}
