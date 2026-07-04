// lib/sensing/rppg/roi_extractor.dart
import 'rppg_config.dart';

/// Frame YUV420 planare, puro Dart (nessuna dipendenza da `package:camera`
/// o Pigeon) — costruibile da `CameraImage` o da byte array sintetici nei
/// test. Stessa forma di `FramePacket` (Fase 2) ma condiviso Android/iOS.
class YuvFrame {
  const YuvFrame({
    required this.width,
    required this.height,
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });

  final int width;
  final int height;
  final List<int> yPlane;
  final List<int> uPlane;
  final List<int> vPlane;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
}

/// Media colore su una ROI. `pixelCount == 0` significa nessuna ROI valida
/// (landmark assenti o poligoni degeneri) — mai inventare un colore.
class RoiColorMeans {
  const RoiColorMeans({
    required this.r,
    required this.g,
    required this.b,
    required this.pixelCount,
  });

  final double r;
  final double g;
  final double b;
  final int pixelCount;

  static const RoiColorMeans empty =
      RoiColorMeans(r: 0, g: 0, b: 0, pixelCount: 0);
}

/// MediaPipe restituisce i landmark nello spazio del frame "raddrizzato"
/// (dopo aver applicato `rotationDegrees` per portarlo upright — Fase 2,
/// `ImageProcessingOptions.setRotationDegrees`). I byte YUV grezzi restano
/// invece nell'orientamento del sensore. Questa funzione inverte quella
/// rotazione per rimappare un punto normalizzato "upright" (xu, yu) sulle
/// coordinate normalizzate del frame grezzo (u, v), pronte per essere
/// moltiplicate per width/height e indicizzare i piani YUV.
(double, double) rawNormalizedFromUpright(
  double xu,
  double yu,
  int rotationDegrees,
) {
  final int normalized = ((rotationDegrees % 360) + 360) % 360;
  return switch (normalized) {
    90 => (yu, 1 - xu),
    180 => (1 - xu, 1 - yu),
    270 => (1 - yu, xu),
    _ => (xu, yu),
  };
}

bool _pointInPolygon(double px, double py, List<(double, double)> polygon) {
  bool inside = false;
  final int n = polygon.length;
  for (int i = 0, j = n - 1; i < n; j = i++) {
    final (double xi, double yi) = polygon[i];
    final (double xj, double yj) = polygon[j];
    final bool intersects = ((yi > py) != (yj > py)) &&
        (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
    if (intersects) {
      inside = !inside;
    }
  }
  return inside;
}

List<List<(double, double)>> _rawPolygons(
  List<double> faceLandmarksFlat,
  int rotationDegrees,
) {
  final List<List<(double, double)>> polygons = <List<(double, double)>>[];
  for (final List<int> indices in <List<int>>[
    RppgConfig.foreheadIndices,
    RppgConfig.leftCheekIndices,
    RppgConfig.rightCheekIndices,
  ]) {
    final List<(double, double)> polygon = <(double, double)>[];
    for (final int index in indices) {
      final int xi = index * 2;
      if (xi + 1 >= faceLandmarksFlat.length) {
        return <List<(double, double)>>[]; // landmark troppo corti: nessuna ROI
      }
      polygon.add(rawNormalizedFromUpright(
        faceLandmarksFlat[xi],
        faceLandmarksFlat[xi + 1],
        rotationDegrees,
      ));
    }
    polygons.add(polygon);
  }
  return polygons;
}

/// Estrae la media RGB dei pixel che ricadono dentro le ROI (fronte +
/// guance) derivate dai landmark facciali. Nessun frame viene salvato: solo
/// una media scalare per canale (NFR1/NFR2).
RoiColorMeans meansForRoi({
  required YuvFrame frame,
  required List<double> faceLandmarksFlat,
  required int rotationDegrees,
}) {
  if (faceLandmarksFlat.isEmpty) {
    return RoiColorMeans.empty;
  }
  final List<List<(double, double)>> polygons =
      _rawPolygons(faceLandmarksFlat, rotationDegrees);
  if (polygons.isEmpty) {
    return RoiColorMeans.empty;
  }

  double minU = 1, maxU = 0, minV = 1, maxV = 0;
  for (final List<(double, double)> polygon in polygons) {
    for (final (double u, double v) in polygon) {
      minU = minU < u ? minU : u;
      maxU = maxU > u ? maxU : u;
      minV = minV < v ? minV : v;
      maxV = maxV > v ? maxV : v;
    }
  }
  final int minCol = (minU * frame.width).floor().clamp(0, frame.width - 1);
  final int maxCol = (maxU * frame.width).ceil().clamp(0, frame.width - 1);
  final int minRow = (minV * frame.height).floor().clamp(0, frame.height - 1);
  final int maxRow = (maxV * frame.height).ceil().clamp(0, frame.height - 1);

  double sumR = 0, sumG = 0, sumB = 0;
  int count = 0;
  for (int row = minRow; row <= maxRow; row++) {
    final double v = (row + 0.5) / frame.height;
    final int uvRow = row >> 1;
    for (int col = minCol; col <= maxCol; col++) {
      final double u = (col + 0.5) / frame.width;
      final bool inside =
          polygons.any((List<(double, double)> p) => _pointInPolygon(u, v, p));
      if (!inside) {
        continue;
      }
      final int uvCol = col >> 1;
      final int yIndex = row * frame.yRowStride + col;
      final int uvIndex = uvRow * frame.uvRowStride + uvCol * frame.uvPixelStride;
      final int yValue = frame.yPlane[yIndex];
      final int uValue = frame.uPlane[uvIndex] - 128;
      final int vValue = frame.vPlane[uvIndex] - 128;

      final double r = (yValue + 1.370705 * vValue).clamp(0, 255);
      final double g =
          (yValue - 0.698001 * vValue - 0.337633 * uValue).clamp(0, 255);
      final double b = (yValue + 1.732446 * uValue).clamp(0, 255);

      sumR += r;
      sumG += g;
      sumB += b;
      count++;
    }
  }

  if (count == 0) {
    return RoiColorMeans.empty;
  }
  return RoiColorMeans(r: sumR / count, g: sumG / count, b: sumB / count, pixelCount: count);
}
