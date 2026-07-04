import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/roi_extractor.dart';

/// Costruisce un [YuvFrame] uniforme (stesso Y/U/V ovunque).
YuvFrame solidFrame({
  required int width,
  required int height,
  required int y,
  required int u,
  required int v,
}) {
  final int chromaW = (width / 2).ceil();
  final int chromaH = (height / 2).ceil();
  return YuvFrame(
    width: width,
    height: height,
    yPlane: List<int>.filled(width * height, y),
    uPlane: List<int>.filled(chromaW * chromaH, u),
    vPlane: List<int>.filled(chromaW * chromaH, v),
    yRowStride: width,
    uvRowStride: chromaW,
    uvPixelStride: 1,
  );
}

/// Landmark piatti [x0,y0,x1,y1,...] con un piccolo quadrato pieno nel
/// centro per fronte/guance (stessi indici di [RppgConfig]), così la ROI
/// ricade sempre dentro il frame.
List<double> centeredLandmarks() {
  final List<double> flat = List<double>.filled(478 * 2, 0.5);
  void put(int i, double x, double y) {
    flat[i * 2] = x;
    flat[i * 2 + 1] = y;
  }

  // Fronte: piccolo quadrato attorno (0.5, 0.3).
  put(10, 0.45, 0.25);
  put(108, 0.55, 0.25);
  put(151, 0.55, 0.35);
  put(337, 0.45, 0.35);
  // Guancia sinistra: quadrato attorno (0.35, 0.5).
  put(205, 0.30, 0.45);
  put(50, 0.40, 0.45);
  put(118, 0.40, 0.55);
  put(101, 0.30, 0.55);
  // Guancia destra: quadrato attorno (0.65, 0.5).
  put(425, 0.60, 0.45);
  put(280, 0.70, 0.45);
  put(347, 0.70, 0.55);
  put(330, 0.60, 0.55);
  return flat;
}

void main() {
  group('rawNormalizedFromUpright', () {
    test('0 degrees is identity', () {
      expect(rawNormalizedFromUpright(0.2, 0.7, 0), (0.2, 0.7));
    });

    test('90 degrees maps (xu, yu) -> (yu, 1 - xu)', () {
      final (double u, double v) result = rawNormalizedFromUpright(0.2, 0.7, 90);
      expect(result.$1, closeTo(0.7, 1e-9));
      expect(result.$2, closeTo(0.8, 1e-9));
    });

    test('180 degrees maps (xu, yu) -> (1 - xu, 1 - yu)', () {
      final (double u, double v) result =
          rawNormalizedFromUpright(0.2, 0.7, 180);
      expect(result.$1, closeTo(0.8, 1e-9));
      expect(result.$2, closeTo(0.3, 1e-9));
    });

    test('270 degrees maps (xu, yu) -> (1 - yu, xu)', () {
      final (double u, double v) result =
          rawNormalizedFromUpright(0.2, 0.7, 270);
      expect(result.$1, closeTo(0.3, 1e-9));
      expect(result.$2, closeTo(0.2, 1e-9));
    });
  });

  group('meansForRoi', () {
    test('mid-gray frame (Y=128,U=128,V=128) averages to ~neutral RGB', () {
      final YuvFrame frame =
          solidFrame(width: 100, height: 100, y: 128, u: 128, v: 128);
      final RoiColorMeans means = meansForRoi(
        frame: frame,
        faceLandmarksFlat: centeredLandmarks(),
        rotationDegrees: 0,
      );
      expect(means.pixelCount, greaterThan(0));
      expect(means.r, closeTo(128, 2));
      expect(means.g, closeTo(128, 2));
      expect(means.b, closeTo(128, 2));
    });

    test('empty landmarks yields zero pixel count', () {
      final YuvFrame frame =
          solidFrame(width: 100, height: 100, y: 128, u: 128, v: 128);
      final RoiColorMeans means = meansForRoi(
        frame: frame,
        faceLandmarksFlat: const <double>[],
        rotationDegrees: 0,
      );
      expect(means.pixelCount, 0);
    });

    test('ROI outside the reddish half stays neutral, not blended', () {
      // Frame verticalmente diviso: metà sinistra rossastra (V alto),
      // metà destra grigia. Le ROI (centrate a x=0.3..0.7) sono tutte a
      // destra della soglia (colonna 60 su 100) tranne la guancia sinistra:
      // qui verifichiamo solo che la guancia destra (x in [0.60,0.70])
      // non sia contaminata dal rosso a sinistra.
      final int width = 100;
      final int height = 100;
      final List<int> yPlane = List<int>.filled(width * height, 128);
      final List<int> uPlane = List<int>.filled(50 * 50, 128);
      final List<int> vPlane = List<int>.generate(50 * 50, (int i) {
        final int col = i % 50;
        return col < 25 ? 200 : 128; // metà sinistra (colonne 0-49 raw) rossastra
      });
      final YuvFrame frame = YuvFrame(
        width: width,
        height: height,
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        yRowStride: width,
        uvRowStride: 50,
        uvPixelStride: 1,
      );
      final List<double> flat = List<double>.filled(478 * 2, 0.5);
      // Solo guancia destra popolata (indici 425/280/347/330), il resto
      // resta a (0.5,0.5) collassando su un unico punto (area zero, non
      // conta pixel extra).
      flat[425 * 2] = 0.75;
      flat[425 * 2 + 1] = 0.45;
      flat[280 * 2] = 0.85;
      flat[280 * 2 + 1] = 0.45;
      flat[347 * 2] = 0.85;
      flat[347 * 2 + 1] = 0.55;
      flat[330 * 2] = 0.75;
      flat[330 * 2 + 1] = 0.55;

      final RoiColorMeans means =
          meansForRoi(frame: frame, faceLandmarksFlat: flat, rotationDegrees: 0);
      expect(means.pixelCount, greaterThan(0));
      // V=128 (neutro) atteso in quella regione -> B non deve salire come
      // succederebbe se V=200 (rossastro) contaminasse la media.
      expect(means.b, closeTo(128, 3));
    });
  });
}
