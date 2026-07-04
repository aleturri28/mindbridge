import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/camera/camera_sensing_source.dart';
import 'package:mindbridge/sensing/camera/sensing_api.g.dart';
import 'package:mindbridge/sensing/camera/visual_metrics.dart';
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
}
