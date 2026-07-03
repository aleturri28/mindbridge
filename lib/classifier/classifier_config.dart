/// Configurazione del classificatore: TUTTI i pesi e le soglie vivono qui,
/// mai hardcoded sparsi (CLAUDE.md). Valori conservativi: meglio una
/// notifica in meno che flapping o falsi positivi a raffica.
class ClassifierConfig {
  const ClassifierConfig({
    this.hrWeight = 0.4,
    this.tensionWeight = 0.35,
    this.postureWeight = 0.25,
    this.minHrQuality = 0.5,
    this.mediumThreshold = 1.0,
    this.highThreshold = 2.0,
    this.highExitThreshold = 1.5,
    this.scoreSmoothingAlpha = 0.3,
    this.highPersistence = const Duration(seconds: 60),
    this.notificationCooldown = const Duration(minutes: 15),
  });

  /// Pesi dei tre segnali nello score complessivo (somma ~1).
  final double hrWeight;
  final double tensionWeight;
  final double postureWeight;

  /// Sotto questa qualità rPPG il contributo hr viene escluso e i pesi
  /// rimanenti rinormalizzati (graceful degradation NFR3).
  final double minHrQuality;

  /// Soglie sullo score smussato (unità: deviazioni standard pesate).
  final double mediumThreshold;
  final double highThreshold;

  /// Isteresi in uscita da ALTO: si scende solo sotto questa soglia,
  /// più bassa di [highThreshold], per evitare flip-flop.
  final double highExitThreshold;

  /// EMA sullo score grezzo (0..1, più basso = più smussato).
  final double scoreSmoothingAlpha;

  /// ALTO scatta solo se lo score resta sopra soglia per questa durata
  /// continuativa (vincolo: ≥ 60 s).
  final Duration highPersistence;

  /// Intervallo minimo tra due notifiche di pausa (vincolo: ≥ 15 min).
  final Duration notificationCooldown;
}
