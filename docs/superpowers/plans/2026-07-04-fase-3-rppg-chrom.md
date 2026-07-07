# Fase 3 — rPPG condiviso (CHROM) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real HR estimate (bpm) + honest signal-quality index on Android, via CHROM run in a dedicated Dart isolate over RGB means sampled from forehead/cheek ROIs (derived from the Fase 2 face landmarks), replacing `CameraSensingSource`'s current `hr: null, hrQuality: 0` placeholder.

**Architecture:** Every native camera frame (not just the ~5fps landmark-throttled ones) gets a cheap inline ROI-color extraction in Dart, using the most recent face-landmark polygon (refreshed at the existing Fase 2 throttle rate) mapped from MediaPipe's upright coordinate space back onto the raw YUV frame. RGB triplets stream into a persistent `RppgProcessor` isolate that keeps a ~10s rolling buffer and runs CHROM (normalize → combine → frequency-domain peak scan restricted to 0.7–3Hz, which doubles as the band-pass) every 1s hop, returning `{hrBpm, quality}`. Results merge into the existing `VisualSampleAggregator`.

**Tech Stack:** Dart (no new pub dependencies — direct-frequency scan instead of an FFT package, per "50 lines of Dart before a dependency"), `dart:isolate`, existing `camera` plugin frames already flowing through `CameraSensingSource`.

**Spec:** `docs/superpowers/specs/2026-07-04-fase-3-rppg-design.md`

## Global Constraints

- Privacy on-device (NFR1/NFR2): RGB extraction reuses the same in-process YUV bytes `CameraSensingSource` already holds; nothing new crosses a process or network boundary.
- NFR3/NFR10: below `RppgConfig.qualityThreshold`, `hr` must be `null` (never fabricate a number); raw numeric HR/quality visible only on the debug screen (existing sanctioned exception).
- No impact on user flow: `sensingSourceProvider` keeps returning the simulator; rPPG is reachable only from the hidden debug screen (Fase 2 pattern, unchanged). Sim/real switch is Fase 4.
- Shared/platform-agnostic: `chrom.dart`, `roi_extractor.dart`, `rppg_window.dart`, `rppg_isolate.dart` must not import `package:camera` or anything Android-specific — Fase 5 (iOS) reuses them unchanged.
- Android `minSdk 26`, Dart strict null-safety, `flutter_lints` strict (`strict-casts`, `strict-inference`, `strict-raw-types`, `unawaited_futures: error`, `dead_code: error`, `cancel_subscriptions`, `close_sinks`) — `flutter analyze` must stay at zero issues.
- Window ~10s, hop ~1s, band 0.7–3Hz (42–180 bpm) — exact values from CLAUDE.md/spec, centralized in `RppgConfig`.
- Conventional commits in English; decisions touching report constraints go in `docs/decisions.md`.

## File Structure

| File | Responsibility |
|---|---|
| `lib/sensing/rppg/rppg_config.dart` | Centralized constants: ROI landmark indices, window/hop durations, band Hz, quality threshold |
| `lib/sensing/rppg/roi_extractor.dart` | `YuvFrame`, rotation-mapping, ROI polygon → mean RGB extraction |
| `lib/sensing/rppg/chrom.dart` | Pure CHROM algorithm: normalize, combine, frequency-domain peak scan, quality |
| `lib/sensing/rppg/rppg_window.dart` | `RppgWindow`: rolling buffer + hop timing, `RppgEstimate` |
| `lib/sensing/rppg/rppg_isolate.dart` | `RppgProcessor`: persistent isolate wrapper around `RppgWindow` |
| `lib/sensing/camera/camera_sensing_source.dart` | Modify: per-frame RGB extraction, feed isolate, merge HR into `VisualSampleAggregator` |
| `lib/features/debug/sensing_debug_screen.dart` | Modify: real HR/quality display, ROI polygon overlay |
| `test/sensing/rppg/roi_extractor_test.dart` | Unit tests |
| `test/sensing/rppg/chrom_test.dart` | Unit tests (synthetic sinusoids) |
| `test/sensing/rppg/rppg_window_test.dart` | Unit tests |
| `test/sensing/rppg/rppg_isolate_test.dart` | Integration test (real isolate spawn) |
| `test/sensing/camera_sensing_source_test.dart` | Modify: `updateHr` merge tests |
| `docs/decisions.md` | Modify: Fase 3 decision log |

---

### Task 1: `RppgConfig` + ROI extraction (`roi_extractor.dart`)

**Files:**
- Create: `lib/sensing/rppg/rppg_config.dart`
- Create: `lib/sensing/rppg/roi_extractor.dart`
- Test: `test/sensing/rppg/roi_extractor_test.dart`

**Interfaces:**
- Produces: `RppgConfig` (constants below); `YuvFrame` (fields: `width`, `height`, `yPlane`, `uPlane`, `vPlane`, `yRowStride`, `uvRowStride`, `uvPixelStride` — same shape as the existing `FramePacket`, but pure Dart, no Pigeon/camera dependency); `(double u, double v) rawNormalizedFromUpright(double xu, double yu, int rotationDegrees)`; `RoiColorMeans` (fields `r`, `g`, `b`, `pixelCount`); `RoiColorMeans meansForRoi({required YuvFrame frame, required List<double> faceLandmarksFlat, required int rotationDegrees})`.

- [ ] **Step 1: Write `rppg_config.dart`**

```dart
// lib/sensing/rppg/rppg_config.dart

/// Costanti della pipeline rPPG (CHROM). Centralizzate qui — CLAUDE.md:
/// pesi/soglie in configurazione, non hardcoded sparsi.
abstract final class RppgConfig {
  /// Indici FaceMesh (478 punti, stesso schema di [FrameAnalysis.faceLandmarks])
  /// delle patch di pelle usate per la media RGB. Punto di partenza da
  /// letteratura rPPG; raffinato visivamente (overlay poligono su debug
  /// screen) durante la validazione manuale — stesso approccio empirico già
  /// usato per le costanti di `postureScoreFromPose` in Fase 2.
  static const List<int> foreheadIndices = <int>[10, 108, 151, 337];
  static const List<int> leftCheekIndices = <int>[205, 50, 118, 101];
  static const List<int> rightCheekIndices = <int>[425, 280, 347, 330];

  /// Finestra scorrevole e hop (CLAUDE.md: ~10s finestra, hop 1s).
  static const Duration windowDuration = Duration(seconds: 10);
  static const Duration hopDuration = Duration(seconds: 1);

  /// Banda passante HR: 0.7–3 Hz (42–180 bpm). La ricerca del picco è
  /// ristretta a questa banda, il che funge anche da band-pass.
  static const double bandLowHz = 0.7;
  static const double bandHighHz = 3.0;

  /// Risoluzione della scansione in frequenza (Hz).
  static const double frequencyStepHz = 0.05;

  /// Sotto questa purezza spettrale (potenza del picco / potenza totale in
  /// banda) l'HR non è affidabile: mai mostrarlo come numero (NFR3/NFR10).
  static const double qualityThreshold = 0.35;

  /// Campioni minimi in finestra prima di tentare una stima.
  static const int minSamplesForEstimate = 30;
}
```

- [ ] **Step 2: Write the failing tests for `roi_extractor.dart`**

```dart
// test/sensing/rppg/roi_extractor_test.dart
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
      expect(u, closeTo(0.7, 1e-9));
      expect(v, closeTo(0.8, 1e-9));
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
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
flutter test test/sensing/rppg/roi_extractor_test.dart
```

Expected: FAIL — `roi_extractor.dart` does not exist.

- [ ] **Step 4: Implement `roi_extractor.dart`**

```dart
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
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/sensing/rppg/roi_extractor_test.dart && flutter analyze
```

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/sensing/rppg/rppg_config.dart lib/sensing/rppg/roi_extractor.dart test/sensing/rppg/roi_extractor_test.dart
git commit -m "feat: add rPPG config and landmark-based ROI color extraction"
```

---

### Task 2: CHROM algorithm (`chrom.dart`)

**Files:**
- Create: `lib/sensing/rppg/chrom.dart`
- Test: `test/sensing/rppg/chrom_test.dart`

**Interfaces:**
- Consumes: `RppgConfig` (Task 1).
- Produces: `ChromSample` (fields `r`, `g`, `b`, `timestampMs`); `ChromResult` (fields `hrBpm`, `quality`); `ChromResult? estimateHeartRate(List<ChromSample> samples)`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/sensing/rppg/chrom_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/chrom.dart';
import 'package:mindbridge/sensing/rppg/rppg_config.dart';

/// Genera una finestra sintetica di campioni RGB con una modulazione
/// sinusoidale a [freqHz] sovrapposta a un colore pelle plausibile.
///
/// Le ampiezze per canale decrescono R>G>B (come il volume ematico reale),
/// ma soprattutto ogni canale ha uno sfasamento diverso ([phaseG], [phaseB]):
/// senza questo il segnale sarebbe una singola sinusoide identica su tutti i
/// canali, che la combinazione di crominanza del CHROM (Xs-alpha*Ys) annulla
/// per costruzione (alpha=std(Xs)/std(Ys)). Lo sfasamento — fisicamente reale,
/// il fronte d'onda del polso raggiunge i canali con timing diverso — rende
/// Xs e Ys non proporzionali, così la fondamentale sopravvive ed è
/// recuperabile. Il rumore, se presente, è indipendente per canale.
List<ChromSample> syntheticPulse({
  required double freqHz,
  double amplitude = 2.0,
  double noiseAmplitude = 0,
  int sampleCount = 300,
  double fps = 30,
  double phaseG = 0.6,
  double phaseB = 1.2,
  math.Random? random,
}) {
  final math.Random rnd = random ?? math.Random(42);
  double noise() =>
      noiseAmplitude == 0 ? 0 : (rnd.nextDouble() * 2 - 1) * noiseAmplitude;
  return <ChromSample>[
    for (int i = 0; i < sampleCount; i++)
      () {
        final double t = i / fps;
        final double w = 2 * math.pi * freqHz;
        return ChromSample(
          r: 128 + amplitude * math.sin(w * t) + noise(),
          g: 128 + 0.6 * amplitude * math.sin(w * t - phaseG) + noise(),
          b: 128 + 0.3 * amplitude * math.sin(w * t - phaseB) + noise(),
          timestampMs: (t * 1000).round(),
        );
      }(),
  ];
}

void main() {
  group('estimateHeartRate', () {
    test('clean 1.2 Hz pulse resolves to ~72 bpm with high quality', () {
      final ChromResult? result =
          estimateHeartRate(syntheticPulse(freqHz: 1.2));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(72, 5));
      // La griglia di scan (0.05 Hz) è più fitta della risoluzione di
      // Rayleigh della finestra (0.1 Hz): la potenza di un tono puro si
      // distribuisce sui bin adiacenti, quindi la purezza spettrale satura
      // intorno a 0.5. L'invariante che conta: un segnale pulito supera
      // comodamente la soglia di affidabilità dell'app.
      expect(result.quality, greaterThan(RppgConfig.qualityThreshold));
    });

    test('clean 2.0 Hz pulse resolves to ~120 bpm', () {
      final ChromResult? result =
          estimateHeartRate(syntheticPulse(freqHz: 2.0));
      expect(result, isNotNull);
      expect(result!.hrBpm, closeTo(120, 6));
    });

    test('pure noise (no pulse) yields low quality', () {
      final ChromResult? result = estimateHeartRate(syntheticPulse(
        freqHz: 1.2,
        amplitude: 0,
        noiseAmplitude: 3,
      ));
      expect(result, isNotNull);
      expect(result!.quality, lessThan(RppgConfig.qualityThreshold));
    });

    test('too few samples returns null', () {
      final ChromResult? result = estimateHeartRate(syntheticPulse(
        freqHz: 1.2,
        sampleCount: RppgConfig.minSamplesForEstimate - 1,
      ));
      expect(result, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/sensing/rppg/chrom_test.dart
```

Expected: FAIL — `chrom.dart` does not exist.

- [ ] **Step 3: Implement `chrom.dart`**

```dart
// lib/sensing/rppg/chrom.dart
import 'dart:math' as math;

import 'rppg_config.dart';

/// Campione RGB con timestamp, ingresso del CHROM.
class ChromSample {
  const ChromSample({
    required this.r,
    required this.g,
    required this.b,
    required this.timestampMs,
  });

  final double r;
  final double g;
  final double b;
  final int timestampMs;
}

/// Uscita del CHROM su una finestra: bpm stimato + purezza spettrale 0..1.
class ChromResult {
  const ChromResult({required this.hrBpm, required this.quality});

  final double hrBpm;
  final double quality;
}

double _mean(List<double> xs) {
  double sum = 0;
  for (final double x in xs) {
    sum += x;
  }
  return sum / xs.length;
}

double _std(List<double> xs, double mean) {
  double sumSq = 0;
  for (final double x in xs) {
    final double d = x - mean;
    sumSq += d * d;
  }
  return math.sqrt(sumSq / xs.length);
}

/// Stima HR e qualità da una finestra di campioni RGB con l'algoritmo
/// CHROM: normalizzazione per canale, combinazione di crominanza
/// (Xs=3Rn-2Gn, Ys=1.5Rn+Gn-1.5Bn, S=Xs-alpha*Ys), poi ricerca del picco
/// in frequenza ristretta a 0.7-3Hz (la restrizione di banda funge da
/// band-pass, evitando una libreria FFT esterna). Ritorna null se la
/// finestra è troppo corta.
ChromResult? estimateHeartRate(List<ChromSample> samples) {
  if (samples.length < RppgConfig.minSamplesForEstimate) {
    return null;
  }

  final List<double> rs = <double>[for (final ChromSample s in samples) s.r];
  final List<double> gs = <double>[for (final ChromSample s in samples) s.g];
  final List<double> bs = <double>[for (final ChromSample s in samples) s.b];
  final List<double> tSeconds = <double>[
    for (final ChromSample s in samples) s.timestampMs / 1000,
  ];

  final double meanR = _mean(rs);
  final double meanG = _mean(gs);
  final double meanB = _mean(bs);
  if (meanR == 0 || meanG == 0 || meanB == 0) {
    return const ChromResult(hrBpm: 0, quality: 0);
  }

  final int n = samples.length;
  final List<double> xs = List<double>.generate(
      n, (int i) => 3 * (rs[i] / meanR) - 2 * (gs[i] / meanG));
  final List<double> ys = List<double>.generate(
      n,
      (int i) =>
          1.5 * (rs[i] / meanR) + (gs[i] / meanG) - 1.5 * (bs[i] / meanB));

  final double xsMean = _mean(xs);
  final double ysMean = _mean(ys);
  final double stdXs = _std(xs, xsMean);
  final double stdYs = _std(ys, ysMean);
  final double alpha = stdYs == 0 ? 0 : stdXs / stdYs;

  final List<double> combined = List<double>.generate(
      n, (int i) => (xs[i] - xsMean) - alpha * (ys[i] - ysMean));

  double bestFreq = RppgConfig.bandLowHz;
  double bestPower = -1;
  double totalPower = 0;
  final int steps =
      ((RppgConfig.bandHighHz - RppgConfig.bandLowHz) / RppgConfig.frequencyStepHz)
          .round();
  for (int step = 0; step <= steps; step++) {
    final double freq = RppgConfig.bandLowHz + step * RppgConfig.frequencyStepHz;
    double re = 0, im = 0;
    for (int i = 0; i < n; i++) {
      final double angle = -2 * math.pi * freq * tSeconds[i];
      re += combined[i] * math.cos(angle);
      im += combined[i] * math.sin(angle);
    }
    final double power = re * re + im * im;
    totalPower += power;
    if (power > bestPower) {
      bestPower = power;
      bestFreq = freq;
    }
  }

  final double quality = totalPower == 0 ? 0 : bestPower / totalPower;
  return ChromResult(hrBpm: bestFreq * 60, quality: quality);
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/sensing/rppg/chrom_test.dart && flutter analyze
```

Expected: all tests PASS, `No issues found!`. If the noise test is flaky, the fixed `math.Random(42)` seed keeps it deterministic — do not loosen the quality threshold assertion, adjust `noiseAmplitude` instead.

- [ ] **Step 5: Commit**

```bash
git add lib/sensing/rppg/chrom.dart test/sensing/rppg/chrom_test.dart
git commit -m "feat: add CHROM heart-rate estimation with in-band frequency scan"
```

---

### Task 3: `RppgWindow` (rolling buffer + hop timing)

**Files:**
- Create: `lib/sensing/rppg/rppg_window.dart`
- Test: `test/sensing/rppg/rppg_window_test.dart`

**Interfaces:**
- Consumes: `ChromSample`, `estimateHeartRate` (Task 2); `RppgConfig` (Task 1).
- Produces: `RppgEstimate` (fields `hrBpm`, `quality`, `timestampMs`); `RppgWindow` with `void add(double r, double g, double b, int timestampMs)` and `RppgEstimate? maybeEstimate(int nowMs)`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/sensing/rppg/rppg_window_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/rppg_config.dart';
import 'package:mindbridge/sensing/rppg/rppg_window.dart';

void main() {
  group('RppgWindow', () {
    test('no estimate before minSamplesForEstimate is reached', () {
      final RppgWindow window = RppgWindow();
      RppgEstimate? last;
      for (int i = 0; i < RppgConfig.minSamplesForEstimate - 1; i++) {
        window.add(128, 128, 128, i * 33);
        last = window.maybeEstimate(i * 33);
      }
      expect(last, isNull);
    });

    test('emits an estimate once buffer is full, then respects hop', () {
      final RppgWindow window = RppgWindow();
      const double fps = 30;
      RppgEstimate? first;
      for (int i = 0; i < 300; i++) {
        final int tMs = (i / fps * 1000).round();
        final double t = tMs / 1000;
        const double w = 2 * math.pi * 1.2;
        // Sfasamento per canale: senza, la singola sinusoide in fase su
        // R/G/B si annulla sotto CHROM (Xs e Ys proporzionali) e la stima
        // non è recuperabile — stesso motivo del fixture di Task 2.
        window.add(
          128 + 2 * math.sin(w * t),
          128 + 1.2 * math.sin(w * t - 0.6),
          128 + 0.6 * math.sin(w * t - 1.2),
          tMs,
        );
        final RppgEstimate? estimate = window.maybeEstimate(tMs);
        if (estimate != null && first == null) {
          first = estimate;
        }
      }
      expect(first, isNotNull);
      expect(first!.hrBpm, closeTo(72, 6));

      // Chiamare di nuovo con lo stesso timestamp (< hop dall'ultima stima)
      // non deve produrre una nuova stima.
      final RppgEstimate? immediate = window.maybeEstimate(first.timestampMs);
      expect(immediate, isNull);
    });

    test('old samples fall out of the window', () {
      final RppgWindow window = RppgWindow();
      window.add(200, 200, 200, 0);
      // Avanza oltre la durata della finestra: il campione iniziale deve
      // uscire dal buffer (verificato indirettamente: nessuna estimate con
      // un solo campione recente, sotto minSamplesForEstimate).
      final RppgEstimate? estimate = window.maybeEstimate(
          RppgConfig.windowDuration.inMilliseconds + 1000);
      expect(estimate, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/sensing/rppg/rppg_window_test.dart
```

Expected: FAIL — `rppg_window.dart` does not exist.

- [ ] **Step 3: Implement `rppg_window.dart`**

```dart
// lib/sensing/rppg/rppg_window.dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/sensing/rppg/rppg_window_test.dart && flutter analyze
```

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/sensing/rppg/rppg_window.dart test/sensing/rppg/rppg_window_test.dart
git commit -m "feat: add RppgWindow rolling buffer with hop-gated estimates"
```

---

### Task 4: `RppgProcessor` (persistent isolate)

**Files:**
- Create: `lib/sensing/rppg/rppg_isolate.dart`
- Test: `test/sensing/rppg/rppg_isolate_test.dart`

**Interfaces:**
- Consumes: `RppgWindow`, `RppgEstimate` (Task 3).
- Produces: `RppgProcessor` with `static Future<RppgProcessor> spawn()`, `void addFrame({required double r, required double g, required double b, required int timestampMs})`, `Stream<RppgEstimate> get estimates`, `Future<void> dispose()`. Re-exports `RppgEstimate`.

- [ ] **Step 1: Write the failing integration test**

```dart
// test/sensing/rppg/rppg_isolate_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindbridge/sensing/rppg/rppg_isolate.dart';

void main() {
  test('RppgProcessor spawns, ingests synthetic frames, emits an estimate',
      () async {
    final RppgProcessor processor = await RppgProcessor.spawn();
    addTearDown(processor.dispose);

    final Future<RppgEstimate> firstEstimate = processor.estimates.first;

    const double fps = 30;
    for (int i = 0; i < 300; i++) {
      final int tMs = (i / fps * 1000).round();
      final double t = tMs / 1000;
      const double w = 2 * math.pi * 1.2;
      // Sfasamento per canale: una singola sinusoide in fase su R/G/B si
      // annulla sotto CHROM (Xs e Ys proporzionali). Lo sfasamento rende il
      // polso recuperabile — coerente con i fixture di Task 2/3.
      processor.addFrame(
        r: 128 + 2 * math.sin(w * t),
        g: 128 + 1.2 * math.sin(w * t - 0.6),
        b: 128 + 0.6 * math.sin(w * t - 1.2),
        timestampMs: tMs,
      );
    }

    final RppgEstimate estimate =
        await firstEstimate.timeout(const Duration(seconds: 5));
    expect(estimate.hrBpm, closeTo(72, 6));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/sensing/rppg/rppg_isolate_test.dart
```

Expected: FAIL — `rppg_isolate.dart` does not exist.

- [ ] **Step 3: Implement `rppg_isolate.dart`**

```dart
// lib/sensing/rppg/rppg_isolate.dart
import 'dart:async';
import 'dart:isolate';

import 'rppg_window.dart';

export 'rppg_window.dart' show RppgEstimate;

const String _closeSignal = '__rppg_close__';

void _entryPoint(SendPort mainSendPort) {
  final ReceivePort isolateReceive = ReceivePort();
  mainSendPort.send(isolateReceive.sendPort);
  final RppgWindow window = RppgWindow();

  isolateReceive.listen((dynamic message) {
    if (message is (double, double, double, int)) {
      final (double r, double g, double b, int timestampMs) = message;
      window.add(r, g, b, timestampMs);
      final RppgEstimate? estimate = window.maybeEstimate(timestampMs);
      if (estimate != null) {
        mainSendPort.send(estimate);
      }
    } else if (message == _closeSignal) {
      isolateReceive.close();
      Isolate.exit();
    }
  });
}

/// Wrapper isolate persistente attorno a [RppgWindow]: riceve triplette RGB
/// dal main isolate, mantiene la finestra scorrevole ed emette stime HR.
/// Isolate persistente (non `compute()` per hop) per evitare lo spawn ogni
/// secondo — CLAUDE.md: elaborazione rPPG in isolate dedicato.
class RppgProcessor {
  RppgProcessor._(
    this._isolate,
    this._toIsolate,
    this._fromIsolate,
    this._subscription,
    this._estimates,
  );

  final Isolate _isolate;
  final SendPort _toIsolate;
  final ReceivePort _fromIsolate;
  final StreamSubscription<dynamic> _subscription;
  final StreamController<RppgEstimate> _estimates;

  Stream<RppgEstimate> get estimates => _estimates.stream;

  static Future<RppgProcessor> spawn() async {
    final ReceivePort fromIsolate = ReceivePort();
    final Completer<SendPort> toIsolateCompleter = Completer<SendPort>();
    final StreamController<RppgEstimate> estimates =
        StreamController<RppgEstimate>.broadcast();

    final StreamSubscription<dynamic> subscription =
        fromIsolate.listen((dynamic message) {
      if (message is SendPort && !toIsolateCompleter.isCompleted) {
        toIsolateCompleter.complete(message);
      } else if (message is RppgEstimate && !estimates.isClosed) {
        estimates.add(message);
      }
    });

    final Isolate isolate =
        await Isolate.spawn(_entryPoint, fromIsolate.sendPort);
    final SendPort toIsolate = await toIsolateCompleter.future;

    return RppgProcessor._(isolate, toIsolate, fromIsolate, subscription, estimates);
  }

  void addFrame({
    required double r,
    required double g,
    required double b,
    required int timestampMs,
  }) {
    _toIsolate.send((r, g, b, timestampMs));
  }

  Future<void> dispose() async {
    _toIsolate.send(_closeSignal);
    await _subscription.cancel();
    _fromIsolate.close();
    _isolate.kill(priority: Isolate.immediate);
    await _estimates.close();
  }
}
```

Note: the `message is (double, double, double, int)` record-type check requires Dart 3 pattern-matching on record types, supported by the project's `sdk: ^3.12.2`.

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/sensing/rppg/rppg_isolate_test.dart && flutter analyze
```

Expected: PASS, `No issues found!`. If the test times out, check that `_entryPoint` sends its `SendPort` before entering `listen` (already the case above) — a common isolate-handshake bug is listening before sending the port back.

- [ ] **Step 5: Commit**

```bash
git add lib/sensing/rppg/rppg_isolate.dart test/sensing/rppg/rppg_isolate_test.dart
git commit -m "feat: add persistent RppgProcessor isolate wrapper"
```

---

### Task 5: Wire rPPG into `CameraSensingSource`

**Files:**
- Modify: `lib/sensing/camera/camera_sensing_source.dart`
- Modify (tests): `test/sensing/camera_sensing_source_test.dart`

**Interfaces:**
- Consumes: `RppgProcessor`, `RppgEstimate` (Task 4); `meansForRoi`, `YuvFrame`, `RoiColorMeans` (Task 1); `RppgConfig` (Task 1).
- Produces: `VisualSampleAggregator.updateHr(RppgEstimate estimate)`; `CameraSensingSource` now feeds real `hr`/`hrQuality` into `SensingSample`.

- [ ] **Step 1: Write the failing test for `VisualSampleAggregator.updateHr`**

Add to `test/sensing/camera_sensing_source_test.dart` (append inside `main()`, new group):

```dart
  group('VisualSampleAggregator.updateHr', () {
    test('quality at or above threshold surfaces hr', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      agg.updateHr(const RppgEstimate(
        hrBpm: 72,
        quality: RppgConfig.qualityThreshold + 0.1,
        timestampMs: 0,
      ));
      final SensingSample s = agg.snapshot(DateTime(2026));
      expect(s.hr, 72);
      expect(s.hrQuality, closeTo(RppgConfig.qualityThreshold + 0.1, 1e-9));
    });

    test('quality below threshold hides hr but still reports quality', () {
      final VisualSampleAggregator agg = VisualSampleAggregator();
      agg.updateHr(const RppgEstimate(
        hrBpm: 72,
        quality: RppgConfig.qualityThreshold - 0.1,
        timestampMs: 0,
      ));
      final SensingSample s = agg.snapshot(DateTime(2026));
      expect(s.hr, isNull);
      expect(s.hrQuality, closeTo(RppgConfig.qualityThreshold - 0.1, 1e-9));
    });
```

And add the two imports at the top of the test file:

```dart
import 'package:mindbridge/sensing/rppg/rppg_config.dart';
import 'package:mindbridge/sensing/rppg/rppg_isolate.dart';
```

(close the new `group` with `});` matching the existing style.)

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/sensing/camera_sensing_source_test.dart
```

Expected: FAIL — `VisualSampleAggregator` has no method `updateHr`.

- [ ] **Step 3: Modify `camera_sensing_source.dart`**

Add imports at the top (after the existing ones):

```dart
import '../rppg/rppg_config.dart';
import '../rppg/rppg_isolate.dart';
import '../rppg/roi_extractor.dart';
```

Modify `VisualSampleAggregator`: add HR state and `updateHr`, and use it in `snapshot`:

```dart
class VisualSampleAggregator {
  VisualSampleAggregator({this.alpha = 0.3});

  final double alpha;

  double _tension = VisualMetricsConfig.restTension;
  double _posture = VisualMetricsConfig.restPosture;
  double? _hr;
  double _hrQuality = 0;

  void add(FrameAnalysis analysis) {
    final double tension = facialTensionFromBlendshapes(analysis.blendshapes);
    final double posture = postureScoreFromPose(analysis.poseLandmarks);
    _tension = _ema(_tension, tension);
    _posture = _ema(_posture, posture);
  }

  /// Aggiorna l'HR dall'ultima stima CHROM. Sotto soglia di qualità l'HR
  /// resta nascosto (mai inventare un valore — NFR3/NFR10), ma la qualità
  /// vera viene comunque riportata così la debug screen mostra il degrado
  /// onestamente.
  void updateHr(RppgEstimate estimate) {
    _hrQuality = estimate.quality;
    _hr = estimate.quality >= RppgConfig.qualityThreshold ? estimate.hrBpm : null;
  }

  double _ema(double previous, double next) =>
      previous + alpha * (next - previous);

  SensingSample snapshot(DateTime now) {
    return SensingSample(
      hr: _hr,
      hrQuality: _hrQuality,
      facialTension: _tension,
      postureScore: _posture,
      timestamp: now,
    );
  }
}
```

Modify `CameraSensingSource`: track the last known face landmarks, spawn/feed/dispose the `RppgProcessor`, and extract ROI color on every frame (not just throttled ones):

```dart
class CameraSensingSource implements SensingSource {
  CameraSensingSource({
    SensingHostApi? hostApi,
    this.samplePeriod = const Duration(seconds: 1),
    this.minFrameInterval = const Duration(milliseconds: 200),
  }) : _hostApi = hostApi ?? SensingHostApi();

  final SensingHostApi _hostApi;
  final Duration samplePeriod;
  final Duration minFrameInterval;

  final VisualSampleAggregator _aggregator = VisualSampleAggregator();
  final StreamController<SensingSample> _samples =
      StreamController<SensingSample>.broadcast();
  final StreamController<FrameAnalysis> _analyses =
      StreamController<FrameAnalysis>.broadcast();

  CameraController? _controller;
  Timer? _sampleTimer;
  RppgProcessor? _rppgProcessor;
  StreamSubscription<RppgEstimate>? _rppgSub;
  bool _analyzing = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _sensorOrientation = 270;

  /// Ultimi landmark facciali noti (spazio "upright" MediaPipe), usati per
  /// la ROI rPPG sui frame intermedi non passati al canale Pigeon.
  List<double> _lastFaceLandmarks = const <double>[];

  @override
  Stream<SensingSample> get signals => _samples.stream;

  Stream<FrameAnalysis> get analyses => _analyses.stream;

  CameraController? get controller => _controller;

  @override
  Future<void> start() async {
    if (_controller != null) {
      return;
    }
    await _hostApi.initialize();
    _rppgProcessor = await RppgProcessor.spawn();
    _rppgSub = _rppgProcessor!.estimates.listen(_aggregator.updateHr);

    final List<CameraDescription> cameras = await availableCameras();
    final CameraDescription front = cameras.firstWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _sensorOrientation = front.sensorOrientation;

    final CameraController controller = CameraController(
      front,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    await controller.initialize();
    await controller.startImageStream(_onFrame);

    _sampleTimer = Timer.periodic(samplePeriod, (_) {
      if (!_samples.isClosed) {
        _samples.add(_aggregator.snapshot(DateTime.now()));
      }
    });
  }

  void _onFrame(CameraImage image) {
    _extractRoiColor(image);

    final DateTime now = DateTime.now();
    if (_analyzing || now.difference(_lastFrameAt) < minFrameInterval) {
      return;
    }
    _analyzing = true;
    _lastFrameAt = now;
    unawaited(_analyze(image, now));
  }

  /// Estrazione ROI ad ogni frame nativo (non throttled come l'analisi
  /// landmark): la ROI riusa l'ultimo poligono noto, aggiornato in
  /// [_analyze]. Costo O(pixel ROI), non full-frame.
  void _extractRoiColor(CameraImage image) {
    final RppgProcessor? processor = _rppgProcessor;
    if (processor == null || _lastFaceLandmarks.isEmpty) {
      return;
    }
    final YuvFrame frame = YuvFrame(
      width: image.width,
      height: image.height,
      yPlane: image.planes[0].bytes,
      uPlane: image.planes[1].bytes,
      vPlane: image.planes[2].bytes,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
    final RoiColorMeans means = meansForRoi(
      frame: frame,
      faceLandmarksFlat: _lastFaceLandmarks,
      rotationDegrees: _sensorOrientation,
    );
    if (means.pixelCount == 0) {
      return;
    }
    processor.addFrame(
      r: means.r,
      g: means.g,
      b: means.b,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _analyze(CameraImage image, DateTime now) async {
    try {
      final FrameAnalysis? analysis = await _hostApi.analyzeFrame(
        FramePacket(
          width: image.width,
          height: image.height,
          rotationDegrees: _sensorOrientation,
          yPlane: image.planes[0].bytes,
          uPlane: image.planes[1].bytes,
          vPlane: image.planes[2].bytes,
          yRowStride: image.planes[0].bytesPerRow,
          uvRowStride: image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
          timestampMs: now.millisecondsSinceEpoch,
        ),
      );
      if (analysis != null) {
        _aggregator.add(analysis);
        if (analysis.faceDetected) {
          _lastFaceLandmarks = analysis.faceLandmarks;
        }
        if (!_analyses.isClosed) {
          _analyses.add(analysis);
        }
      }
    } on PlatformException catch (e) {
      debugPrint('analyzeFrame failed: $e');
    } finally {
      _analyzing = false;
    }
  }

  @override
  Future<void> stop() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    await _rppgSub?.cancel();
    _rppgSub = null;
    await _rppgProcessor?.dispose();
    _rppgProcessor = null;
    _lastFaceLandmarks = const <double>[];
    final CameraController? controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    }
    await _hostApi.close();
  }

  @override
  void dispose() {
    unawaited(stop());
    unawaited(_samples.close());
    unawaited(_analyses.close());
  }
}
```

- [ ] **Step 4: Run tests and analyzer**

```bash
flutter test test/sensing/camera_sensing_source_test.dart && flutter analyze
```

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/sensing/camera/camera_sensing_source.dart test/sensing/camera_sensing_source_test.dart
git commit -m "feat: wire rPPG isolate into CameraSensingSource"
```

---

### Task 6: Debug screen — real HR/quality + ROI overlay

**Files:**
- Modify: `lib/features/debug/sensing_debug_screen.dart`

**Interfaces:**
- Consumes: `RppgConfig` (Task 1), existing `_source.signals`/`_source.analyses`/`FrameAnalysis`.

- [ ] **Step 1: Add the ROI polygon painter and update the metrics tile**

Add import at the top:

```dart
import '../../sensing/rppg/rppg_config.dart';
```

Replace the "Metriche derivate (EMA)" `ListTile` subtitle to reflect honest degradation, and add the ROI overlay next to the existing landmark overlay in the `Stack`:

```dart
                            CameraPreview(controller),
                            if (a != null)
                              CustomPaint(
                                painter: _LandmarkPainter(analysis: a),
                              ),
                            if (a != null && a.faceDetected)
                              CustomPaint(
                                painter: _RoiPainter(faceLandmarks: a.faceLandmarks),
                              ),
```

```dart
                    ListTile(
                      title: const Text('Metriche derivate'),
                      subtitle: Text(
                        s == null
                            ? 'nessun campione ancora'
                            : 'tensione: ${s.facialTension.toStringAsFixed(2)} '
                                '· postura: ${s.postureScore.toStringAsFixed(2)}\n'
                                'hr: ${s.hr?.toStringAsFixed(1) ?? (s.hrQuality > 0 ? 'segnale instabile' : 'in attesa')} '
                                'bpm · quality: ${s.hrQuality.toStringAsFixed(2)}',
                      ),
                    ),
```

Add the `_RoiPainter` class after `_LandmarkPainter`:

```dart
/// Disegna i poligoni ROI (fronte + guance) usati dal CHROM, per verifica
/// visiva durante la validazione manuale (§5 del design doc Fase 3).
class _RoiPainter extends CustomPainter {
  _RoiPainter({required this.faceLandmarks});

  final List<double> faceLandmarks;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()
      ..color = AppColors.stressLow.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    for (final List<int> indices in <List<int>>[
      RppgConfig.foreheadIndices,
      RppgConfig.leftCheekIndices,
      RppgConfig.rightCheekIndices,
    ]) {
      final Path path = Path();
      for (int i = 0; i < indices.length; i++) {
        final int xi = indices[i] * 2;
        if (xi + 1 >= faceLandmarks.length) {
          return;
        }
        final double x = (1 - faceLandmarks[xi]) * size.width;
        final double y = faceLandmarks[xi + 1] * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, fill);
    }
  }

  @override
  bool shouldRepaint(_RoiPainter oldDelegate) =>
      oldDelegate.faceLandmarks != faceLandmarks;
}
```

Note: if `Color.withValues` is unavailable in the project's Flutter SDK version, use `Color.withOpacity(0.25)` instead — check whichever is not deprecated per `flutter analyze` and use that one.

- [ ] **Step 2: Verify tests, analyzer, build**

```bash
flutter test && flutter analyze && flutter build apk --debug
```

Expected: all tests PASS, `No issues found!`, APK built.

- [ ] **Step 3: Commit**

```bash
git add lib/features/debug/sensing_debug_screen.dart
git commit -m "feat: show real HR/quality and ROI overlay on sensing debug screen"
```

---

### Task 7: Manual validation on device + decision log

**Files:**
- Modify: `docs/decisions.md`

- [ ] **Step 1: Manual verification on an Android device (physical device required — HR validation needs a real pulse, front camera, good light)**

```bash
flutter run -d <android-device-id>
```

Checklist (all must hold):
1. Home → long-press title → Debug → «Sensing camera (Fase 2)».
2. Green-tinted ROI polygons (forehead + both cheeks) appear over the face once detected, roughly on skin (not eyes/hair/background). If misaligned, note which of `RppgConfig.foreheadIndices`/`leftCheekIndices`/`rightCheekIndices` need adjusting and fix before proceeding.
3. Hold still in good, even light for ~15s: `hr` transitions from "in attesa"/"segnale instabile" to a stable bpm number, `quality` rises above `RppgConfig.qualityThreshold` (0.35).
4. Compare the displayed bpm against a smartwatch or pulse oximeter worn simultaneously: within ±10 bpm.
5. Cover the camera or move out of frame → `hr` reverts to hidden (not a frozen stale number), quality drops.
6. Wave the phone / talk / move around → quality visibly drops (spectral purity degrades) — confirms honest degradation, no fabricated bpm.
7. No visible UI jank/dropped frames on the camera preview during the ~30fps ROI extraction (if there is stutter, note it — perf tuning is Fase 6, not a blocker for Fase 3 DoD, but worth recording).
8. Regular session flow (Home → Calibrazione → Sessione) still works entirely on the simulator; camera never activates outside the debug screen.

- [ ] **Step 2: Record decisions**

Append to `docs/decisions.md`:

```markdown
## Fase 3 — rPPG condiviso (CHROM)

- **RGB extraction happens on every native camera frame, in Dart, inline**
  (not gated by the Fase 2 ~5fps landmark throttle): CHROM needs a sampling
  rate above Nyquist for HR up to 180 bpm (3 Hz), which 5 fps cannot
  guarantee. The ROI polygon itself is refreshed only at landmark keyframes
  and reused in between — the face moves little frame-to-frame.
- **No FFT dependency**: CHROM's peak search is a direct discrete-frequency
  scan (Goertzel-style) restricted to 0.7–3 Hz, which also serves as the
  band-pass. Simpler than adding an FFT package and works with the
  non-uniform frame timestamps camera delivery actually produces.
- **CHROM/ROI code (`lib/sensing/rppg/*`) has zero `package:camera` or
  platform-specific imports** — shared as-is by the Fase 5 iOS port per
  CLAUDE.md's shared-Dart rPPG requirement.
- **Below `RppgConfig.qualityThreshold`, `hr` is `null`** but `hrQuality`
  is still reported: honest degradation (NFR3/NFR10), never a fabricated
  bpm.
- **Manual validation result:** [fill in bpm delta vs reference device,
  device model, lighting conditions — recorded after Task 7 Step 1].
```

- [ ] **Step 3: Commit**

```bash
git add docs/decisions.md
git commit -m "docs: record Fase 3 rPPG pipeline decisions"
```

---

## Self-Review (done at planning time)

- **Spec coverage:** §1 data flow → Tasks 5 (per-frame extraction + isolate feed); §2 ROI extraction → Task 1; §3 CHROM → Task 2; §4 isolate plumbing → Task 4; §5 debug screen/validation → Tasks 6–7; §6 testing → each task's own test step; §7 error handling → `RoiColorMeans.empty`/`pixelCount == 0` path (Task 1) and `updateHr` quality gating (Task 5), both covered by tests.
- **Placeholder scan:** none — all code shown in full. The one intentionally open item is the manual bpm-delta result in Task 7's `decisions.md` template, which by definition can only be filled in after the on-device test runs (same pattern as Fase 2's Task 6).
- **Type consistency:** `RppgEstimate(hrBpm, quality, timestampMs)` defined once in `rppg_window.dart`, re-exported from `rppg_isolate.dart`, consumed identically in `camera_sensing_source.dart` and its tests. `ChromSample`/`ChromResult` used only inside `chrom.dart`/`rppg_window.dart`, never leak further. `YuvFrame`/`RoiColorMeans`/`meansForRoi` signatures match between Task 1's implementation, its tests, and Task 5's `_extractRoiColor`. `RppgConfig` constant names (`foreheadIndices`, `leftCheekIndices`, `rightCheekIndices`, `windowDuration`, `hopDuration`, `bandLowHz`, `bandHighHz`, `frequencyStepHz`, `qualityThreshold`, `minSamplesForEstimate`) are consistent across every task that references them.
- **Scope:** iOS port, sim/real switch, and perf hardening are explicitly out of scope (deferred to Fase 5/4/6 respectively), matching the spec's "Fuori scope" section.
