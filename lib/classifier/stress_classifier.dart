import 'dart:math';

import '../sensing/sensing_sample.dart';
import 'baseline.dart';
import 'classifier_config.dart';
import 'stress_level.dart';

/// Risultato della classificazione di un campione.
class ClassifierOutput {
  const ClassifierOutput({required this.level, required this.shouldNotify});

  final StressLevel level;

  /// True solo alla transizione verso ALTO sostenuto (≥ highPersistence),
  /// fuori dal cooldown e da eventuale snooze. Al massimo una volta per
  /// episodio: chi ascolta mostra la proposta di pausa (FR4).
  final bool shouldNotify;
}

/// Classificatore euristico di stress: score pesato delle deviazioni dalla
/// baseline personale, con smussamento, isteresi e cooldown. Puro Dart,
/// deterministico rispetto ai timestamp dei campioni (testabile senza clock).
///
/// Non è una misura clinica: le soglie sono conservative e l'output resta
/// un'etichetta (mai numeri all'utente, NFR10).
class StressClassifier {
  StressClassifier({
    required this._baseline,
    this._config = const ClassifierConfig(),
  });

  final Baseline _baseline;
  final ClassifierConfig _config;

  double? _smoothedScore;
  StressLevel _level = StressLevel.basso;
  DateTime? _highCandidateSince;
  DateTime? _lastNotifiedAt;
  DateTime? _snoozeUntil;
  DateTime? _lastTimestamp;

  /// Score smussato corrente (solo per debug screen, mai in UI utente).
  double get debugScore => _smoothedScore ?? 0;

  /// Posticipa la prossima notifica (bottone «Posticipa 20 min», FR4).
  void notifySnoozed(Duration snooze) {
    final DateTime from = _lastTimestamp ?? DateTime.now();
    _snoozeUntil = from.add(snooze);
  }

  /// Riparte pulito (nuova sessione).
  void reset() {
    _smoothedScore = null;
    _level = StressLevel.basso;
    _highCandidateSince = null;
    _lastNotifiedAt = null;
    _snoozeUntil = null;
    _lastTimestamp = null;
  }

  ClassifierOutput process(SensingSample sample) {
    _lastTimestamp = sample.timestamp;
    final double raw = _rawScore(sample);
    final double alpha = _config.scoreSmoothingAlpha;
    final double score = _smoothedScore == null
        ? raw
        : alpha * raw + (1 - alpha) * _smoothedScore!;
    _smoothedScore = score;

    _updateLevel(score, sample.timestamp);

    return ClassifierOutput(
      level: _level,
      shouldNotify: _shouldNotify(sample.timestamp),
    );
  }

  /// Deviazioni positive dalla baseline, in unità di deviazione standard,
  /// clampate a ≥ 0 e pesate. La postura è invertita: peggiora scendendo.
  double _rawScore(SensingSample sample) {
    final bool hrUsable = sample.hr != null &&
        sample.hrQuality >= _config.minHrQuality &&
        _baseline.hasHr;

    final double zHr = hrUsable
        ? max(0, (sample.hr! - _baseline.hrMean) / _baseline.hrStd)
        : 0;
    final double zTension = max(
      0,
      (sample.facialTension - _baseline.tensionMean) / _baseline.tensionStd,
    );
    final double zPosture = max(
      0,
      (_baseline.postureMean - sample.postureScore) / _baseline.postureStd,
    );

    double weightSum =
        _config.tensionWeight + _config.postureWeight;
    double score =
        _config.tensionWeight * zTension + _config.postureWeight * zPosture;
    if (hrUsable) {
      weightSum += _config.hrWeight;
      score += _config.hrWeight * zHr;
    }
    // Rinormalizza: senza hr i segnali restanti pesano per intero
    // (graceful degradation, non score artificialmente basso).
    return score / weightSum;
  }

  void _updateLevel(double score, DateTime at) {
    // Candidatura ad ALTO: parte quando lo score supera la soglia e regge
    // solo se resta sopra ininterrottamente per highPersistence.
    if (score >= _config.highThreshold) {
      _highCandidateSince ??= at;
      final Duration sustained = at.difference(_highCandidateSince!);
      if (sustained >= _config.highPersistence) {
        _level = StressLevel.alto;
        return;
      }
    } else {
      _highCandidateSince = null;
    }

    if (_level == StressLevel.alto) {
      // Isteresi in uscita: da ALTO si scende solo sotto highExitThreshold.
      if (score < _config.highExitThreshold) {
        _level = score >= _config.mediumThreshold
            ? StressLevel.medio
            : StressLevel.basso;
      }
      return;
    }

    _level = score >= _config.mediumThreshold
        ? StressLevel.medio
        : StressLevel.basso;
  }

  bool _shouldNotify(DateTime at) {
    if (_level != StressLevel.alto) {
      return false;
    }
    if (_lastNotifiedAt != null &&
        at.difference(_lastNotifiedAt!) < _config.notificationCooldown) {
      return false;
    }
    if (_snoozeUntil != null && at.isBefore(_snoozeUntil!)) {
      return false;
    }
    _lastNotifiedAt = at;
    _snoozeUntil = null;
    return true;
  }
}
