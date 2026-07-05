import 'chrom.dart';
import 'rppg_config.dart';

/// Stima HR pubblica: bpm + qualità + timestamp della stima.
class RppgEstimate {
  const RppgEstimate({
    required this.hrBpm,
    required this.quality,
    required this.timestampMs,
  });

  final double hrBpm;
  final double quality;
  final int timestampMs;
}

/// Buffer scorrevole (~10s) di campioni RGB + timing dell'hop (~1s). Pura:
/// nessuna dipendenza da isolate/camera, testabile in isolamento.
class RppgWindow {
  RppgWindow({
    this.windowDuration = RppgConfig.windowDuration,
    this.hopDuration = RppgConfig.hopDuration,
  });

  final Duration windowDuration;
  final Duration hopDuration;

  final List<ChromSample> _buffer = <ChromSample>[];
  int? _lastEstimateMs;

  void add(double r, double g, double b, int timestampMs) {
    _buffer.add(ChromSample(r: r, g: g, b: b, timestampMs: timestampMs));
    final int cutoff = timestampMs - windowDuration.inMilliseconds;
    _buffer.removeWhere((ChromSample s) => s.timestampMs < cutoff);
  }

  /// Ritorna una nuova stima se è passato almeno [hopDuration] dall'ultima
  /// (o se non è mai stata calcolata), altrimenti null.
  RppgEstimate? maybeEstimate(int nowMs) {
    final int? last = _lastEstimateMs;
    if (last != null && nowMs - last < hopDuration.inMilliseconds) {
      return null;
    }
    final ChromResult? result = estimateHeartRate(_buffer);
    if (result == null) {
      return null;
    }
    _lastEstimateMs = nowMs;
    return RppgEstimate(
      hrBpm: result.hrBpm,
      quality: result.quality,
      timestampMs: nowMs,
    );
  }
}
