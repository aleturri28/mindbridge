/// Pesi e costanti della derivazione metrica visiva. Centralizzati qui
/// (convenzione CLAUDE.md: pesi in configurazione, non hardcoded sparsi).
abstract final class VisualMetricsConfig {
  /// Valori neutri usati quando il segnale manca: coerenti col profilo
  /// «a riposo» del simulatore, così l'assenza di volto/posa non spinge
  /// mai il classifier verso ALTO.
  static const double restTension = 0.15;
  static const double restPosture = 0.9;

  /// Pesi della tensione facciale (somma = 1).
  static const double browWeight = 0.5;
  static const double squintWeight = 0.3;
  static const double mouthWeight = 0.2;

  /// Il rapporto collo/spalle (distanza verticale orecchie→spalle
  /// normalizzata sulla larghezza spalle) mappa [slouchRatio, uprightRatio]
  /// → [0, 1]. Valori empirici da vista frontale a mezzo busto.
  static const double slouchRatio = 0.25;
  static const double uprightRatio = 0.85;

  /// Penalità massima per spalle inclinate (asimmetria).
  static const double tiltPenalty = 0.5;
}

/// Indici (MediaPipe Pose) nella lista piatta [x0, y0, x1, y1, ...].
const int _leftEar = 7;
const int _rightEar = 8;
const int _leftShoulder = 11;
const int _rightShoulder = 12;

/// Tensione facciale 0..1 dai blendshapes MediaPipe (media pesata di
/// corrugamento fronte, strizzamento occhi, compressione labbra).
/// Blendshapes assenti → valore di riposo (mai inventare tensione).
double facialTensionFromBlendshapes(Map<String, double> blendshapes) {
  if (blendshapes.isEmpty) {
    return VisualMetricsConfig.restTension;
  }
  double avg(String left, String right) =>
      ((blendshapes[left] ?? 0) + (blendshapes[right] ?? 0)) / 2;

  final double tension =
      VisualMetricsConfig.browWeight * avg('browDownLeft', 'browDownRight') +
          VisualMetricsConfig.squintWeight *
              avg('eyeSquintLeft', 'eyeSquintRight') +
          VisualMetricsConfig.mouthWeight *
              avg('mouthPressLeft', 'mouthPressRight');
  return tension.clamp(0, 1);
}

/// Punteggio postura 0..1 (1 = eretta e aperta) dai landmark della posa
/// in coordinate normalizzate. Proxy 2D da vista frontale: testa che
/// «affonda» tra le spalle (rapporto collo/spalle) + spalle inclinate.
/// Landmark assenti o degeneri → valore di riposo.
double postureScoreFromPose(List<double> poseLandmarks) {
  if (poseLandmarks.length < (_rightShoulder + 1) * 2) {
    return VisualMetricsConfig.restPosture;
  }
  double x(int i) => poseLandmarks[i * 2];
  double y(int i) => poseLandmarks[i * 2 + 1];

  final double shoulderWidth = (x(_leftShoulder) - x(_rightShoulder)).abs();
  if (shoulderWidth < 1e-3) {
    return VisualMetricsConfig.restPosture;
  }

  final double earMidY = (y(_leftEar) + y(_rightEar)) / 2;
  final double shoulderMidY = (y(_leftShoulder) + y(_rightShoulder)) / 2;

  // y cresce verso il basso: spalle sotto le orecchie → rapporto positivo.
  final double neckRatio = (shoulderMidY - earMidY) / shoulderWidth;
  final double uprightness = (neckRatio - VisualMetricsConfig.slouchRatio) /
      (VisualMetricsConfig.uprightRatio - VisualMetricsConfig.slouchRatio);

  final double tilt =
      (y(_leftShoulder) - y(_rightShoulder)).abs() / shoulderWidth;
  final double score =
      uprightness - VisualMetricsConfig.tiltPenalty * tilt.clamp(0, 1);
  return score.clamp(0, 1);
}
