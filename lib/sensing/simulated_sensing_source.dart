import 'dart:async';
import 'dart:math';

import 'sensing_sample.dart';
import 'sensing_source.dart';

/// Sorgente simulata: genera campioni plausibili interpolando tra un
/// profilo «a riposo» e uno «sotto stress» in base a [targetStress],
/// pilotabile dal menu debug. Serve per demo affidabili, screenshot e
/// sviluppo UI senza camera — resta selezionabile per sempre.
class SimulatedSensingSource implements SensingSource {
  SimulatedSensingSource({
    this.samplePeriod = const Duration(seconds: 1),
    Random? random,
  }) : _random = random ?? Random();

  /// Profilo a riposo (coerente con la baseline attesa da calibrazione).
  static const double _restHr = 65;
  static const double _restTension = 0.15;
  static const double _restPosture = 0.9;

  /// Profilo a stress massimo.
  static const double _stressHr = 100;
  static const double _stressTension = 0.8;
  static const double _stressPosture = 0.45;

  final Duration samplePeriod;
  final Random _random;

  /// 0..1: 0 = riposo, 1 = massimo stress simulato.
  double targetStress = 0;

  /// Qualità rPPG simulata; abbassarla dal debug menu per provare la
  /// graceful degradation del classifier.
  double simulatedHrQuality = 0.9;

  final StreamController<SensingSample> _controller =
      StreamController<SensingSample>.broadcast();
  Timer? _timer;

  @override
  Stream<SensingSample> get signals => _controller.stream;

  @override
  Future<void> start() async {
    _timer ??= Timer.periodic(samplePeriod, (_) => _emit());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_controller.close());
  }

  void _emit() {
    if (_controller.isClosed) {
      return;
    }
    final double t = targetStress.clamp(0, 1);
    final double quality = (simulatedHrQuality + _noise(0.05)).clamp(0.0, 1.0);
    _controller.add(
      SensingSample(
        hr: quality < 0.5
            ? null
            : _lerp(_restHr, _stressHr, t) + _noise(2.5),
        hrQuality: quality,
        facialTension:
            (_lerp(_restTension, _stressTension, t) + _noise(0.04))
                .clamp(0.0, 1.0),
        postureScore:
            (_lerp(_restPosture, _stressPosture, t) + _noise(0.04))
                .clamp(0.0, 1.0),
        timestamp: DateTime.now(),
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Rumore uniforme in [-amplitude, amplitude].
  double _noise(double amplitude) =>
      (_random.nextDouble() * 2 - 1) * amplitude;
}
