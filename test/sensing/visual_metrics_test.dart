import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/camera/visual_metrics.dart';

/// Costruisce la lista piatta [x0,y0,...] per i 33 landmark della posa,
/// piazzando solo naso (0), orecchie (7, 8) e spalle (11, 12).
List<double> pose({
  required (double, double) nose,
  required (double, double) leftEar,
  required (double, double) rightEar,
  required (double, double) leftShoulder,
  required (double, double) rightShoulder,
}) {
  final List<double> flat = List<double>.filled(33 * 2, 0);
  void put(int i, (double, double) p) {
    flat[i * 2] = p.$1;
    flat[i * 2 + 1] = p.$2;
  }

  put(0, nose);
  put(7, leftEar);
  put(8, rightEar);
  put(11, leftShoulder);
  put(12, rightShoulder);
  return flat;
}

void main() {
  group('facialTensionFromBlendshapes', () {
    test('relaxed face scores near zero', () {
      expect(
        facialTensionFromBlendshapes(const <String, double>{
          'browDownLeft': 0.02,
          'browDownRight': 0.03,
          'eyeSquintLeft': 0.05,
          'eyeSquintRight': 0.05,
          'mouthPressLeft': 0.01,
          'mouthPressRight': 0.01,
        }),
        lessThan(0.1),
      );
    });

    test('frowning squinting face scores high', () {
      expect(
        facialTensionFromBlendshapes(const <String, double>{
          'browDownLeft': 0.9,
          'browDownRight': 0.85,
          'eyeSquintLeft': 0.7,
          'eyeSquintRight': 0.75,
          'mouthPressLeft': 0.6,
          'mouthPressRight': 0.6,
        }),
        greaterThan(0.6),
      );
    });

    test('empty blendshapes falls back to rest value', () {
      expect(
        facialTensionFromBlendshapes(const <String, double>{}),
        VisualMetricsConfig.restTension,
      );
    });

    test('result is clamped to 0..1', () {
      final double t = facialTensionFromBlendshapes(const <String, double>{
        'browDownLeft': 1,
        'browDownRight': 1,
        'eyeSquintLeft': 1,
        'eyeSquintRight': 1,
        'mouthPressLeft': 1,
        'mouthPressRight': 1,
      });
      expect(t, inInclusiveRange(0, 1));
    });
  });

  group('postureScoreFromPose', () {
    test('upright posture scores high', () {
      final double score = postureScoreFromPose(pose(
        nose: (0.5, 0.20),
        leftEar: (0.55, 0.22),
        rightEar: (0.45, 0.22),
        leftShoulder: (0.65, 0.50),
        rightShoulder: (0.35, 0.50),
      ));
      expect(score, greaterThan(0.7));
    });

    test('slouched posture (head sunk toward shoulders) scores low', () {
      final double score = postureScoreFromPose(pose(
        nose: (0.5, 0.40),
        leftEar: (0.55, 0.42),
        rightEar: (0.45, 0.42),
        leftShoulder: (0.65, 0.50),
        rightShoulder: (0.35, 0.50),
      ));
      expect(score, lessThan(0.5));
    });

    test('tilted shoulders lower the score vs level shoulders', () {
      final double level = postureScoreFromPose(pose(
        nose: (0.5, 0.20),
        leftEar: (0.55, 0.22),
        rightEar: (0.45, 0.22),
        leftShoulder: (0.65, 0.50),
        rightShoulder: (0.35, 0.50),
      ));
      final double tilted = postureScoreFromPose(pose(
        nose: (0.5, 0.20),
        leftEar: (0.55, 0.22),
        rightEar: (0.45, 0.22),
        leftShoulder: (0.65, 0.42),
        rightShoulder: (0.35, 0.58),
      ));
      expect(tilted, lessThan(level));
    });

    test('empty landmarks falls back to rest value', () {
      expect(
        postureScoreFromPose(const <double>[]),
        VisualMetricsConfig.restPosture,
      );
    });

    test('result is clamped to 0..1', () {
      final double score = postureScoreFromPose(pose(
        nose: (0.5, 0.05),
        leftEar: (0.55, 0.06),
        rightEar: (0.45, 0.06),
        leftShoulder: (0.65, 0.95),
        rightShoulder: (0.35, 0.95),
      ));
      expect(score, inInclusiveRange(0, 1));
    });
  });
}
