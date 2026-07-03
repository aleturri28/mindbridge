import 'package:flutter/foundation.dart';

/// Campione istantaneo dei segnali di sensing (simulati o reali).
///
/// Privacy (NFR1/NFR2): contiene solo metriche derivate, mai frame o
/// immagini. È l'unico dato che attraversa il confine sensing → classifier.
@immutable
class SensingSample {
  const SensingSample({
    required this.hrQuality,
    required this.facialTension,
    required this.postureScore,
    required this.timestamp,
    this.hr,
    this.breathingRate,
  });

  /// Battito stimato in bpm; null quando il segnale non è affidabile
  /// (graceful degradation NFR3: mai inventare valori).
  final double? hr;

  /// Qualità del segnale rPPG, 0..1. Sotto soglia il classifier
  /// ignora [hr] e rinormalizza i pesi.
  final double hrQuality;

  /// Atti respiratori al minuto; null in Fase 1 (non stimato).
  final double? breathingRate;

  /// Tensione facciale 0..1 (0 = viso rilassato).
  final double facialTension;

  /// Punteggio postura 0..1 (1 = postura a riposo, aperta).
  final double postureScore;

  final DateTime timestamp;
}
