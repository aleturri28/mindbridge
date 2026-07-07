import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/camera/camera_sensing_source.dart';
import 'package:mindbridge/sensing/camera/sensing_api.g.dart';
import 'package:mindbridge/sensing/camera/visual_metrics.dart';
import 'package:mindbridge/sensing/rppg/rppg_config.dart';
import 'package:mindbridge/sensing/rppg/rppg_isolate.dart';
import 'package:mindbridge/sensing/sensing_sample.dart';

FrameAnalysis analysis({
  Map<String, double> blendshapes = const <String, double>{},
  bool face = true,
}) {
  return FrameAnalysis(
    faceDetected: face,
    faceLandmarks: const <double>[],
    blendshapes: blendshapes,
    poseDetected: false,
    poseLandmarks: const <double>[],
    inferenceTimeMs: 30,
    timestampMs: 0,
  );
}

void main() {
  group('VisualSampleAggregator', () {
    test('no analyses yet emits rest values with hr null, quality 0', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      final SensingSample s = agg.snapshot(DateTime(2026));
      expect(s.hr, isNull);
      expect(s.hrQuality, 0);
      expect(s.facialTension, VisualMetricsConfig.restTension);
      expect(s.postureScore, VisualMetricsConfig.restPosture);
    });

    test('EMA smooths a tension spike instead of jumping', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      agg.add(analysis(blendshapes: const <String, double>{
        'browDownLeft': 0.1,
        'browDownRight': 0.1,
      }));
      final double before = agg.snapshot(DateTime(2026)).facialTension;
      agg.add(analysis(blendshapes: const <String, double>{
        'browDownLeft': 1,
        'browDownRight': 1,
        'eyeSquintLeft': 1,
        'eyeSquintRight': 1,
        'mouthPressLeft': 1,
        'mouthPressRight': 1,
      }));
      final double after = agg.snapshot(DateTime(2026)).facialTension;
      expect(after, greaterThan(before));
      // Un solo campione estremo non porta la EMA al massimo.
      expect(after, lessThan(0.9));
    });

    test('repeated identical analyses converge to their value', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      for (int i = 0; i < 50; i++) {
        agg.add(analysis(blendshapes: const <String, double>{
          'browDownLeft': 0.8,
          'browDownRight': 0.8,
        }));
      }
      final double tension = agg.snapshot(DateTime(2026)).facialTension;
      // Solo browDown pesato 0.5 → converge verso 0.4.
      expect(tension, closeTo(0.4, 0.05));
    });
  });

  group('VisualSampleAggregator.updateHr', () {
    final DateTime base = DateTime(2026);

    RppgEstimate est(double bpm, {double quality = 0.2}) =>
        RppgEstimate(hrBpm: bpm, quality: quality, timestampMs: 0);

    test('a single estimate is not enough to surface hr', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      agg.updateHr(est(72), now: base);
      final SensingSample s = agg.snapshot(base);
      expect(s.hr, isNull);
      expect(s.hrQuality, 0);
    });

    test('enough consistent estimates surface the median hr', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      agg.updateHr(est(71), now: base);
      agg.updateHr(est(72), now: base.add(const Duration(seconds: 1)));
      agg.updateHr(est(73), now: base.add(const Duration(seconds: 2)));
      final SensingSample s = agg.snapshot(base.add(const Duration(seconds: 2)));
      expect(s.hr, 72); // mediana di 71,72,73
      expect(s.hrQuality, closeTo(0.2, 1e-9));
    });

    test('a single spike is ignored when enough estimates cluster', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      const List<double> bpms = <double>[70, 71, 72, 73, 150];
      for (int i = 0; i < bpms.length; i++) {
        agg.updateHr(est(bpms[i]), now: base.add(Duration(seconds: i)));
      }
      final SensingSample s = agg.snapshot(base.add(const Duration(seconds: 4)));
      expect(s.hr, 72); // mediana robusta; il picco 150 è un outlier
    });

    test('scattered estimates (noise) keep hr null', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      const List<double> bpms = <double>[50, 90, 130, 75, 160];
      for (int i = 0; i < bpms.length; i++) {
        agg.updateHr(est(bpms[i]), now: base.add(Duration(seconds: i)));
      }
      final SensingSample s = agg.snapshot(base.add(const Duration(seconds: 4)));
      expect(s.hr, isNull);
      expect(s.hrQuality, 0);
    });

    test('estimates below the anti-noise floor are ignored', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      for (int i = 0; i < 3; i++) {
        agg.updateHr(
          est(72, quality: RppgConfig.qualityThreshold - 0.01),
          now: base.add(Duration(seconds: i)),
        );
      }
      final SensingSample s = agg.snapshot(base.add(const Duration(seconds: 2)));
      expect(s.hr, isNull);
    });

    test('estimates outside the consistency window are dropped', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      agg.updateHr(est(71), now: base);
      agg.updateHr(est(72), now: base.add(const Duration(seconds: 1)));
      agg.updateHr(est(73), now: base.add(const Duration(seconds: 2)));
      // Molto oltre la finestra di consistenza: le stime recenti sono scadute.
      final DateTime late = base
          .add(RppgConfig.hrConsistencyWindow)
          .add(const Duration(seconds: 10));
      final SensingSample s = agg.snapshot(late);
      expect(s.hr, isNull);
      expect(s.hrQuality, 0);
    });
  });
}
