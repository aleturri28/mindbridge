import 'dart:math';

import '../sensing/sensing_sample.dart';

/// Baseline personale a riposo (FR8), calcolata dalla calibrazione di ~60 s:
/// media e deviazione standard di battito, tensione facciale e postura.
class Baseline {
  const Baseline({
    required this.hrMean,
    required this.hrStd,
    required this.tensionMean,
    required this.tensionStd,
    required this.postureMean,
    required this.postureStd,
  });

  factory Baseline.fromSamples(List<SensingSample> samples) {
    assert(samples.isNotEmpty, 'baseline richiede almeno un campione');
    final List<double> hr = <double>[
      for (final SensingSample s in samples)
        if (s.hr != null) s.hr!,
    ];
    final List<double> tension =
        samples.map((SensingSample s) => s.facialTension).toList();
    final List<double> posture =
        samples.map((SensingSample s) => s.postureScore).toList();

    final (double hrMean, double hrStd) =
        hr.isEmpty ? (0, _minStd) : _meanStd(hr);
    final (double tensionMean, double tensionStd) = _meanStd(tension);
    final (double postureMean, double postureStd) = _meanStd(posture);
    return Baseline(
      hrMean: hrMean,
      hrStd: hrStd,
      tensionMean: tensionMean,
      tensionStd: tensionStd,
      postureMean: postureMean,
      postureStd: postureStd,
    );
  }

  factory Baseline.fromJson(Map<String, dynamic> json) {
    return Baseline(
      hrMean: (json['hrMean'] as num).toDouble(),
      hrStd: (json['hrStd'] as num).toDouble(),
      tensionMean: (json['tensionMean'] as num).toDouble(),
      tensionStd: (json['tensionStd'] as num).toDouble(),
      postureMean: (json['postureMean'] as num).toDouble(),
      postureStd: (json['postureStd'] as num).toDouble(),
    );
  }

  /// Deviazione minima: evita divisioni per ~0 con segnali molto stabili
  /// (una persona ferma non deve produrre z-score esplosivi).
  static const double _minStd = 1e-3;

  final double hrMean;
  final double hrStd;
  final double tensionMean;
  final double tensionStd;
  final double postureMean;
  final double postureStd;

  /// True se la calibrazione ha visto abbastanza battito da usare l'hr.
  bool get hasHr => hrMean > 0;

  Map<String, double> toJson() => <String, double>{
        'hrMean': hrMean,
        'hrStd': hrStd,
        'tensionMean': tensionMean,
        'tensionStd': tensionStd,
        'postureMean': postureMean,
        'postureStd': postureStd,
      };

  static (double, double) _meanStd(List<double> values) {
    final double mean =
        values.reduce((double a, double b) => a + b) / values.length;
    final double variance = values
            .map((double v) => (v - mean) * (v - mean))
            .reduce((double a, double b) => a + b) /
        values.length;
    return (mean, max(sqrt(variance), _minStd));
  }
}
