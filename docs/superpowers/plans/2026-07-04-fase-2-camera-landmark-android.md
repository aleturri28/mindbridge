# Fase 2 — Pipeline camera + MediaPipe landmark (Android) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real visual signals (facial tension, posture) on Android via camera image stream → Pigeon channel → MediaPipe Face/Pose Landmarker in Kotlin, shown on a hidden debug screen with landmark overlay, FPS and raw values. Zero impact on the user-facing session flow (which keeps using `SimulatedSensingSource`).

**Architecture:** The Flutter `camera` plugin streams YUV420 frames in Dart. Each throttled frame is sent over a Pigeon host API (running on a serial background thread) to Kotlin, which converts YUV→Bitmap, runs MediaPipe Face Landmarker (with blendshapes) and Pose Landmarker in VIDEO mode, and returns only landmarks + blendshapes (never frames persist anywhere — privacy NFR1/NFR2 hold: everything stays in-process, on-device, no network). Dart derives `facialTension` and `postureScore` with pure, unit-tested functions, and `CameraSensingSource` (implements the existing `SensingSource`) emits smoothed `SensingSample`s with `hr: null, hrQuality: 0` (rPPG is Fase 3).

**Tech Stack:** Flutter/Dart (Riverpod, existing), `camera` plugin, `pigeon` (codegen), MediaPipe Tasks Vision (Kotlin, `com.google.mediapipe:tasks-vision`), bundled `.task` models in Android assets.

## Global Constraints

- Privacy on-device (NFR1/NFR2): no frame or biometric data leaves the device; no network permission; channel carries only landmarks/metrics results (frames go Dart→Kotlin in-process only, never stored).
- NFR10: raw numeric values visible ONLY in debug screens (they are the sanctioned exception; keep them unlocalized on purpose, like `debug_screen.dart`).
- No impact on user flow: `sensingSourceProvider` keeps returning the simulator; the camera pipeline is reachable only from the hidden debug menu. The sim/real switch is Fase 4.
- Android `minSdk 26`, Kotlin, JVM 17 (already configured). iOS port is Fase 5 — do not touch `ios/`.
- Dart strict null-safety, `flutter_lints` strict: `flutter analyze` must stay at zero issues.
- In-app user-facing strings in Italian via l10n/arb — debug screens are exempt (existing convention).
- Conventional commits in English; decisions touching report constraints go in `docs/decisions.md`.
- Camera at `ResolutionPreset.low`, front camera, `ImageFormatGroup.yuv420`.

## File Structure

| File | Responsibility |
|---|---|
| `pigeons/sensing_api.dart` | Pigeon API definition (FramePacket in, FrameAnalysis out) |
| `lib/sensing/camera/sensing_api.g.dart` | Generated Dart side (do not hand-edit) |
| `android/app/src/main/kotlin/it/unitn/mindbridge/SensingApi.g.kt` | Generated Kotlin side (do not hand-edit) |
| `android/app/src/main/kotlin/it/unitn/mindbridge/LandmarkAnalyzer.kt` | Implements host API: YUV→Bitmap, MediaPipe detect, map results |
| `android/app/src/main/kotlin/it/unitn/mindbridge/MainActivity.kt` | Registers `LandmarkAnalyzer` on the Flutter engine |
| `android/app/src/main/assets/mediapipe/*.task` | Bundled Face/Pose Landmarker models |
| `lib/sensing/camera/visual_metrics.dart` | Pure functions: blendshapes→facialTension, pose landmarks→postureScore |
| `lib/sensing/camera/camera_sensing_source.dart` | `SensingSource` impl: camera stream, throttle, channel, EMA, emit samples |
| `lib/features/debug/sensing_debug_screen.dart` | Hidden debug screen: preview + landmark overlay + FPS + raw values |
| `test/sensing/visual_metrics_test.dart` | Unit tests for metric derivation |
| `test/sensing/camera_sensing_source_test.dart` | Unit tests for aggregation/EMA logic |

---

### Task 1: Dependencies + Pigeon API + codegen

**Files:**
- Modify: `pubspec.yaml`
- Create: `pigeons/sensing_api.dart`
- Create (generated): `lib/sensing/camera/sensing_api.g.dart`
- Create (generated): `android/app/src/main/kotlin/it/unitn/mindbridge/SensingApi.g.kt`

**Interfaces:**
- Produces: `SensingHostApi` (Dart class from codegen) with `Future<void> initialize()`, `Future<FrameAnalysis?> analyzeFrame(FramePacket packet)`, `Future<void> close()`; data classes `FramePacket`, `FrameAnalysis` (fields below). Kotlin interface `SensingHostApi` with matching methods.

- [ ] **Step 1: Add dependencies**

```bash
cd /Users/alessandroturri/dev/mindbridge
flutter pub add camera
flutter pub add --dev pigeon
```

Expected: `camera` (^0.11.x) in `dependencies`, `pigeon` (latest) in `dev_dependencies`, `flutter pub get` succeeds.

- [ ] **Step 2: Write the Pigeon definition**

```dart
// pigeons/sensing_api.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/sensing/camera/sensing_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/it/unitn/mindbridge/SensingApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'it.unitn.mindbridge'),
  ),
)

/// Un frame YUV420 dalla camera Flutter. Vive solo il tempo dell'analisi:
/// il nativo non lo salva né lo inoltra (NFR1/NFR2).
class FramePacket {
  FramePacket({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.timestampMs,
  });

  int width;
  int height;

  /// Rotazione da applicare perché il frame risulti upright
  /// (sensorOrientation della camera frontale, tipicamente 270).
  int rotationDegrees;

  Uint8List yPlane;
  Uint8List uPlane;
  Uint8List vPlane;
  int yRowStride;
  int uvRowStride;
  int uvPixelStride;
  int timestampMs;
}

/// Risultato dell'analisi: SOLO landmark e blendshapes, mai pixel.
class FrameAnalysis {
  FrameAnalysis({
    required this.faceDetected,
    required this.faceLandmarks,
    required this.blendshapes,
    required this.poseDetected,
    required this.poseLandmarks,
    required this.inferenceTimeMs,
    required this.timestampMs,
  });

  bool faceDetected;

  /// Coordinate normalizzate [x0, y0, x1, y1, ...] nello spazio del frame
  /// ruotato (478 punti → 956 valori); vuoto se nessun volto.
  List<double> faceLandmarks;

  /// Nome blendshape → score 0..1; vuoto se nessun volto.
  Map<String, double> blendshapes;

  bool poseDetected;

  /// Come [faceLandmarks], 33 punti → 66 valori; vuoto se nessuna posa.
  List<double> poseLandmarks;

  int inferenceTimeMs;
  int timestampMs;
}

@HostApi()
abstract class SensingHostApi {
  /// Carica i modelli MediaPipe dagli asset. Idempotente.
  void initialize();

  /// Analizza un frame. Ritorna null se il landmarker non è pronto.
  /// Gira su thread in background per non bloccare la UI nativa.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  FrameAnalysis? analyzeFrame(FramePacket packet);

  /// Rilascia i landmarker.
  void close();
}
```

- [ ] **Step 3: Run codegen**

```bash
dart run pigeon --input pigeons/sensing_api.dart
```

Expected: creates `lib/sensing/camera/sensing_api.g.dart` and `android/app/src/main/kotlin/it/unitn/mindbridge/SensingApi.g.kt` with no errors.

- [ ] **Step 4: Verify analyzer is clean**

```bash
flutter analyze
```

Expected: `No issues found!` (generated files are lint-clean; if the generated Dart file trips strict lints, add `// ignore_for_file:` is NOT needed — pigeon output ships with its own ignores. If analyze still complains, exclude nothing; fix by regenerating with latest pigeon.)

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock pigeons/ lib/sensing/camera/sensing_api.g.dart android/app/src/main/kotlin/it/unitn/mindbridge/SensingApi.g.kt
git commit -m "feat: add camera dependency and pigeon sensing channel API"
```

---

### Task 2: Android native — MediaPipe landmarkers behind the channel

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/assets/mediapipe/face_landmarker.task` (downloaded)
- Create: `android/app/src/main/assets/mediapipe/pose_landmarker_lite.task` (downloaded)
- Create: `android/app/src/main/kotlin/it/unitn/mindbridge/LandmarkAnalyzer.kt`
- Modify: `android/app/src/main/kotlin/it/unitn/mindbridge/MainActivity.kt`

**Interfaces:**
- Consumes: Kotlin `SensingHostApi`, `FramePacket`, `FrameAnalysis` from Task 1 codegen.
- Produces: a registered host API — Dart's `SensingHostApi.analyzeFrame` works end-to-end on Android.

- [ ] **Step 1: Add MediaPipe dependency**

In `android/app/build.gradle.kts`, `dependencies` block:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // MediaPipe Tasks: Face/Pose Landmarker on-device (NFR1: nessuna rete).
    implementation("com.google.mediapipe:tasks-vision:0.10.26.1")
}
```

(If `0.10.26.1` is not resolvable, fall back to `0.10.14` — API used below is stable across both.)

- [ ] **Step 2: Add camera permission to the manifest**

In `android/app/src/main/AndroidManifest.xml`, after the existing permissions:

```xml
    <!-- Fase 2: sensing passivo via camera frontale. I frame restano
         on-device e in-process; nessun permesso di rete (NFR1/NFR2). -->
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera.front" android:required="false"/>
```

- [ ] **Step 3: Download and bundle the models**

```bash
mkdir -p android/app/src/main/assets/mediapipe
curl -L -o android/app/src/main/assets/mediapipe/face_landmarker.task \
  https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task
curl -L -o android/app/src/main/assets/mediapipe/pose_landmarker_lite.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
ls -la android/app/src/main/assets/mediapipe/
```

Expected: two files of a few MB each (face ~3.7 MB, pose ~5.5 MB). They are committed to the repo (models bundled at build time = no runtime download, coherent with the no-network constraint).

- [ ] **Step 4: Write `LandmarkAnalyzer.kt`**

```kotlin
package it.unitn.mindbridge

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker

/**
 * Implementa il lato nativo del canale sensing: riceve un FramePacket
 * (YUV420), lo converte in Bitmap, esegue Face + Pose Landmarker e
 * restituisce SOLO landmark e blendshapes. Il bitmap è locale al metodo:
 * nessun frame viene salvato o inoltrato (NFR1/NFR2).
 */
class LandmarkAnalyzer(private val context: Context) : SensingHostApi {

    private var faceLandmarker: FaceLandmarker? = null
    private var poseLandmarker: PoseLandmarker? = null

    override fun initialize() {
        if (faceLandmarker != null) return

        faceLandmarker = FaceLandmarker.createFromOptions(
            context,
            FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath("mediapipe/face_landmarker.task")
                        .build()
                )
                .setRunningMode(RunningMode.VIDEO)
                .setNumFaces(1)
                .setOutputFaceBlendshapes(true)
                .build()
        )
        poseLandmarker = PoseLandmarker.createFromOptions(
            context,
            PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath("mediapipe/pose_landmarker_lite.task")
                        .build()
                )
                .setRunningMode(RunningMode.VIDEO)
                .setNumPoses(1)
                .build()
        )
    }

    override fun analyzeFrame(packet: FramePacket): FrameAnalysis? {
        val face = faceLandmarker ?: return null
        val pose = poseLandmarker ?: return null

        val started = SystemClock.uptimeMillis()
        val bitmap = yuv420ToBitmap(packet)
        val mpImage = BitmapImageBuilder(bitmap).build()
        val options = ImageProcessingOptions.builder()
            .setRotationDegrees(packet.rotationDegrees.toInt())
            .build()

        val faceResult = face.detectForVideo(mpImage, options, packet.timestampMs)
        val poseResult = pose.detectForVideo(mpImage, options, packet.timestampMs)

        val faceLandmarks = mutableListOf<Double>()
        val blendshapes = mutableMapOf<String, Double>()
        val faceFound = faceResult.faceLandmarks().isNotEmpty()
        if (faceFound) {
            for (lm in faceResult.faceLandmarks()[0]) {
                faceLandmarks.add(lm.x().toDouble())
                faceLandmarks.add(lm.y().toDouble())
            }
            faceResult.faceBlendshapes().ifPresent { all ->
                for (category in all[0]) {
                    blendshapes[category.categoryName()] =
                        category.score().toDouble()
                }
            }
        }

        val poseLandmarks = mutableListOf<Double>()
        val poseFound = poseResult.landmarks().isNotEmpty()
        if (poseFound) {
            for (lm in poseResult.landmarks()[0]) {
                poseLandmarks.add(lm.x().toDouble())
                poseLandmarks.add(lm.y().toDouble())
            }
        }

        return FrameAnalysis(
            faceDetected = faceFound,
            faceLandmarks = faceLandmarks,
            blendshapes = blendshapes,
            poseDetected = poseFound,
            poseLandmarks = poseLandmarks,
            inferenceTimeMs = SystemClock.uptimeMillis() - started,
            timestampMs = packet.timestampMs,
        )
    }

    override fun close() {
        faceLandmarker?.close()
        faceLandmarker = null
        poseLandmarker?.close()
        poseLandmarker = null
    }

    /** Conversione YUV420 (planare, con stride) → Bitmap ARGB_8888. */
    private fun yuv420ToBitmap(packet: FramePacket): Bitmap {
        val width = packet.width.toInt()
        val height = packet.height.toInt()
        val y = packet.yPlane
        val u = packet.uPlane
        val v = packet.vPlane
        val yRowStride = packet.yRowStride.toInt()
        val uvRowStride = packet.uvRowStride.toInt()
        val uvPixelStride = packet.uvPixelStride.toInt()

        val pixels = IntArray(width * height)
        var index = 0
        for (row in 0 until height) {
            val yRow = row * yRowStride
            val uvRow = (row shr 1) * uvRowStride
            for (col in 0 until width) {
                val yValue = (y[yRow + col].toInt() and 0xFF)
                val uvOffset = uvRow + (col shr 1) * uvPixelStride
                val uValue = (u[uvOffset].toInt() and 0xFF) - 128
                val vValue = (v[uvOffset].toInt() and 0xFF) - 128

                var r = yValue + (1.370705f * vValue).toInt()
                var g = yValue - (0.698001f * vValue).toInt() -
                    (0.337633f * uValue).toInt()
                var b = yValue + (1.732446f * uValue).toInt()
                r = r.coerceIn(0, 255)
                g = g.coerceIn(0, 255)
                b = b.coerceIn(0, 255)
                pixels[index++] =
                    (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}
```

Note for the implementer: the generated Kotlin data classes use `Long` for Dart `int` — hence the `.toInt()` calls; if codegen produced `Long` fields named differently, adapt accessors to the generated file, not vice versa.

- [ ] **Step 5: Register the API in `MainActivity.kt`**

```kotlin
package it.unitn.mindbridge

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var analyzer: LandmarkAnalyzer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        analyzer = LandmarkAnalyzer(applicationContext)
        SensingHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, analyzer)
    }

    override fun onDestroy() {
        analyzer?.close()
        analyzer = null
        super.onDestroy()
    }
}
```

(If the generated companion is `SensingHostApi.Companion.setUp` or takes extra args, follow the generated signature.)

- [ ] **Step 6: Verify the Android build compiles**

```bash
flutter build apk --debug
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. Kotlin compilation errors here mean a mismatch with the generated file — fix `LandmarkAnalyzer.kt` accessors against `SensingApi.g.kt`.

- [ ] **Step 7: Commit**

```bash
git add android/
git commit -m "feat: add MediaPipe face/pose landmarker behind pigeon channel (Android)"
```

---

### Task 3: Visual metrics — pure Dart, TDD

**Files:**
- Create: `lib/sensing/camera/visual_metrics.dart`
- Test: `test/sensing/visual_metrics_test.dart`

**Interfaces:**
- Produces: `double facialTensionFromBlendshapes(Map<String, double> blendshapes)` → 0..1; `double postureScoreFromPose(List<double> poseLandmarks)` → 0..1 (1 = upright/open). Both total functions: empty/missing input → conservative defaults (tension 0, posture 1? NO — see code: missing data returns the neutral rest value so the classifier is never pushed toward ALTO by absent signal).

- [ ] **Step 1: Write the failing tests**

```dart
// test/sensing/visual_metrics_test.dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/sensing/visual_metrics_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'mindbridge/sensing/camera/visual_metrics.dart'` (file does not exist yet).

- [ ] **Step 3: Implement `visual_metrics.dart`**

```dart
// lib/sensing/camera/visual_metrics.dart

/// Pesi e costanti della derivazione metrica visiva. Centralizzati qui
/// (convenzione CLAUDE.md: pesi in configurazione, non hardcoded sparsi).
abstract final class VisualMetricsConfig {
  /// Valori neutri usati quando il segnale manca: coerenti col profilo
  /// «a riposo» del simulatore, così l'assenza di volto/posa non spinge
  /// mai il classifier verso ALTO.
  static const double restTension = 0.15;
  static const double restPosture = 0.9;

  /// Pesi della tensione facciale (somma = 1).
  static const double browWeight = 0.5;
  static const double squintWeight = 0.3;
  static const double mouthWeight = 0.2;

  /// Il rapporto collo/spalle (distanza verticale orecchie→spalle
  /// normalizzata sulla larghezza spalle) mappa [slouchRatio, uprightRatio]
  /// → [0, 1]. Valori empirici da vista frontale a mezzo busto.
  static const double slouchRatio = 0.25;
  static const double uprightRatio = 0.85;

  /// Penalità massima per spalle inclinate (asimmetria).
  static const double tiltPenalty = 0.5;
}

/// Indici (MediaPipe Pose) nella lista piatta [x0, y0, x1, y1, ...].
const int _nose = 0;
const int _leftEar = 7;
const int _rightEar = 8;
const int _leftShoulder = 11;
const int _rightShoulder = 12;

/// Tensione facciale 0..1 dai blendshapes MediaPipe (media pesata di
/// corrugamento fronte, strizzamento occhi, compressione labbra).
/// Blendshapes assenti → valore di riposo (mai inventare tensione).
double facialTensionFromBlendshapes(Map<String, double> blendshapes) {
  if (blendshapes.isEmpty) {
    return VisualMetricsConfig.restTension;
  }
  double avg(String left, String right) =>
      ((blendshapes[left] ?? 0) + (blendshapes[right] ?? 0)) / 2;

  final double tension =
      VisualMetricsConfig.browWeight * avg('browDownLeft', 'browDownRight') +
          VisualMetricsConfig.squintWeight *
              avg('eyeSquintLeft', 'eyeSquintRight') +
          VisualMetricsConfig.mouthWeight *
              avg('mouthPressLeft', 'mouthPressRight');
  return tension.clamp(0, 1);
}

/// Punteggio postura 0..1 (1 = eretta e aperta) dai landmark della posa
/// in coordinate normalizzate. Proxy 2D da vista frontale: testa che
/// «affonda» tra le spalle (rapporto collo/spalle) + spalle inclinate.
/// Landmark assenti o degeneri → valore di riposo.
double postureScoreFromPose(List<double> poseLandmarks) {
  if (poseLandmarks.length < (_rightShoulder + 1) * 2) {
    return VisualMetricsConfig.restPosture;
  }
  double x(int i) => poseLandmarks[i * 2];
  double y(int i) => poseLandmarks[i * 2 + 1];

  final double shoulderWidth = (x(_leftShoulder) - x(_rightShoulder)).abs();
  if (shoulderWidth < 1e-3) {
    return VisualMetricsConfig.restPosture;
  }

  final double earMidY = (y(_leftEar) + y(_rightEar)) / 2;
  final double shoulderMidY = (y(_leftShoulder) + y(_rightShoulder)) / 2;

  // y cresce verso il basso: spalle sotto le orecchie → rapporto positivo.
  final double neckRatio = (shoulderMidY - earMidY) / shoulderWidth;
  final double uprightness = (neckRatio - VisualMetricsConfig.slouchRatio) /
      (VisualMetricsConfig.uprightRatio - VisualMetricsConfig.slouchRatio);

  final double tilt =
      (y(_leftShoulder) - y(_rightShoulder)).abs() / shoulderWidth;
  final double score =
      uprightness - VisualMetricsConfig.tiltPenalty * tilt.clamp(0, 1);
  return score.clamp(0, 1);
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/sensing/visual_metrics_test.dart && flutter analyze
```

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/sensing/camera/visual_metrics.dart test/sensing/visual_metrics_test.dart
git commit -m "feat: derive facial tension and posture score from landmarks"
```

---

### Task 4: `CameraSensingSource`

**Files:**
- Create: `lib/sensing/camera/camera_sensing_source.dart`
- Test: `test/sensing/camera_sensing_source_test.dart`

**Interfaces:**
- Consumes: `SensingSource`/`SensingSample` (existing), `SensingHostApi`, `FramePacket`, `FrameAnalysis` (Task 1), `facialTensionFromBlendshapes`, `postureScoreFromPose` (Task 3), `camera` plugin.
- Produces: `CameraSensingSource implements SensingSource` with `Stream<FrameAnalysis> get analyses` (extra stream for the debug overlay) and `CameraController? get controller` (for `CameraPreview`); testable inner class `VisualSampleAggregator` with `void add(FrameAnalysis analysis)` and `SensingSample snapshot(DateTime now)`.

The testable logic (EMA smoothing, rest-fallback on signal loss) lives in `VisualSampleAggregator`, a pure class with no camera or channel dependency. `CameraSensingSource` is thin plumbing around it.

- [ ] **Step 1: Write the failing tests for the aggregator**

```dart
// test/sensing/camera_sensing_source_test.dart
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
        'browDownLeft': 0.1, 'browDownRight': 0.1,
      }));
      final double before = agg.snapshot(DateTime(2026)).facialTension;
      agg.add(analysis(blendshapes: const <String, double>{
        'browDownLeft': 1, 'browDownRight': 1,
        'eyeSquintLeft': 1, 'eyeSquintRight': 1,
        'mouthPressLeft': 1, 'mouthPressRight': 1,
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
          'browDownLeft': 0.8, 'browDownRight': 0.8,
        }));
      }
      final double tension = agg.snapshot(DateTime(2026)).facialTension;
      // Solo browDown pesato 0.5 → converge verso 0.4.
      expect(tension, closeTo(0.4, 0.05));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/sensing/camera_sensing_source_test.dart
```

Expected: FAIL — `camera_sensing_source.dart` does not exist.

- [ ] **Step 3: Implement `camera_sensing_source.dart`**

```dart
// lib/sensing/camera/camera_sensing_source.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../sensing_sample.dart';
import '../sensing_source.dart';
import 'sensing_api.g.dart';
import 'visual_metrics.dart';

/// Aggrega le [FrameAnalysis] in metriche lisciate (EMA) e produce
/// [SensingSample]. Pura e testabile: nessuna dipendenza da camera/canale.
class VisualSampleAggregator {
  VisualSampleAggregator({this.alpha = 0.3});

  /// Fattore EMA: peso del campione nuovo.
  final double alpha;

  double _tension = VisualMetricsConfig.restTension;
  double _posture = VisualMetricsConfig.restPosture;

  void add(FrameAnalysis analysis) {
    final double tension =
        facialTensionFromBlendshapes(analysis.blendshapes);
    final double posture = postureScoreFromPose(analysis.poseLandmarks);
    _tension = _ema(_tension, tension);
    _posture = _ema(_posture, posture);
  }

  double _ema(double previous, double next) =>
      previous + alpha * (next - previous);

  /// Campione corrente. hr/hrQuality restano vuoti finché l'rPPG non
  /// arriva (Fase 3): mai inventare valori (NFR3).
  SensingSample snapshot(DateTime now) {
    return SensingSample(
      hr: null,
      hrQuality: 0,
      facialTension: _tension,
      postureScore: _posture,
      timestamp: now,
    );
  }
}

/// Sorgente reale (Fase 2, Android): camera frontale a bassa risoluzione →
/// canale Pigeon → MediaPipe nativo → metriche visive. hr arriva in Fase 3.
/// I frame non lasciano mai il processo (NFR1/NFR2).
class CameraSensingSource implements SensingSource {
  CameraSensingSource({
    SensingHostApi? hostApi,
    this.samplePeriod = const Duration(seconds: 1),
    this.minFrameInterval = const Duration(milliseconds: 200),
  }) : _hostApi = hostApi ?? SensingHostApi();

  final SensingHostApi _hostApi;
  final Duration samplePeriod;

  /// Throttle: al massimo un frame ogni [minFrameInterval] (≈5 fps) e mai
  /// più di un'analisi in volo (i frame in eccesso vengono scartati).
  final Duration minFrameInterval;

  final VisualSampleAggregator _aggregator = VisualSampleAggregator();
  final StreamController<SensingSample> _samples =
      StreamController<SensingSample>.broadcast();
  final StreamController<FrameAnalysis> _analyses =
      StreamController<FrameAnalysis>.broadcast();

  CameraController? _controller;
  Timer? _sampleTimer;
  bool _analyzing = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _sensorOrientation = 270;

  @override
  Stream<SensingSample> get signals => _samples.stream;

  /// Analisi grezze per la debug screen (overlay landmark, FPS).
  Stream<FrameAnalysis> get analyses => _analyses.stream;

  /// Controller esposto per `CameraPreview` nella debug screen.
  CameraController? get controller => _controller;

  @override
  Future<void> start() async {
    if (_controller != null) {
      return;
    }
    await _hostApi.initialize();

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
    final DateTime now = DateTime.now();
    if (_analyzing || now.difference(_lastFrameAt) < minFrameInterval) {
      return;
    }
    _analyzing = true;
    _lastFrameAt = now;
    unawaited(_analyze(image, now));
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

Note: `PlatformException` needs `import 'package:flutter/services.dart';` — add it.

- [ ] **Step 4: Run tests and analyzer**

```bash
flutter test test/sensing/camera_sensing_source_test.dart && flutter analyze
```

Expected: all tests PASS, `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/sensing/camera/camera_sensing_source.dart test/sensing/camera_sensing_source_test.dart
git commit -m "feat: add CameraSensingSource with throttled frame analysis and EMA"
```

---

### Task 5: Sensing debug screen with landmark overlay

**Files:**
- Create: `lib/features/debug/sensing_debug_screen.dart`
- Modify: `lib/core/routing/app_router.dart` (new route)
- Modify: `lib/features/debug/debug_screen.dart` (entry point + fix stale subtitle)

**Interfaces:**
- Consumes: `CameraSensingSource` (Task 4: `controller`, `analyses`, `signals`), `AppSpacing` tokens, existing `AppRoutes` pattern.
- Produces: route `AppRoutes.debugSensing = '/debug/sensing'` reachable from the debug menu (Android only).

- [ ] **Step 1: Implement the screen**

```dart
// lib/features/debug/sensing_debug_screen.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../sensing/camera/camera_sensing_source.dart';
import '../../sensing/camera/sensing_api.g.dart';
import '../../sensing/sensing_sample.dart';

/// Debug screen Fase 2 (nascosta, solo dal menu debug): preview camera con
/// overlay dei landmark, FPS e valori grezzi. Qui i numeri sono consentiti
/// (eccezione NFR10, come debug_screen.dart). Testi non localizzati di
/// proposito. Nessun frame viene salvato: solo rendering della preview.
class SensingDebugScreen extends StatefulWidget {
  const SensingDebugScreen({super.key});

  @override
  State<SensingDebugScreen> createState() => _SensingDebugScreenState();
}

class _SensingDebugScreenState extends State<SensingDebugScreen> {
  // Sorgente locale alla schermata: il flusso utente resta sul simulatore.
  final CameraSensingSource _source = CameraSensingSource();
  FrameAnalysis? _lastAnalysis;
  SensingSample? _lastSample;
  String? _error;
  DateTime? _lastFrameTime;
  double _fps = 0;
  StreamSubscription<FrameAnalysis>? _analysisSub;
  StreamSubscription<SensingSample>? _sampleSub;

  @override
  void initState() {
    super.initState();
    _analysisSub = _source.analyses.listen((FrameAnalysis a) {
      final DateTime now = DateTime.now();
      final DateTime? previous = _lastFrameTime;
      setState(() {
        _lastAnalysis = a;
        if (previous != null) {
          final int deltaMs = now.difference(previous).inMilliseconds;
          if (deltaMs > 0) {
            _fps = 1000 / deltaMs;
          }
        }
        _lastFrameTime = now;
      });
    });
    _sampleSub = _source.signals
        .listen((SensingSample s) => setState(() => _lastSample = s));
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _source.start();
      if (mounted) {
        setState(() {});
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = 'Camera non disponibile: ${e.code}');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_analysisSub?.cancel());
    unawaited(_sampleSub?.cancel());
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _source.controller;
    final FrameAnalysis? a = _lastAnalysis;
    final SensingSample? s = _lastSample;

    return Scaffold(
      appBar: AppBar(title: const Text('Debug — sensing camera')),
      body: _error != null
          ? Center(child: Text(_error!))
          : controller == null || !controller.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: <Widget>[
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            CameraPreview(controller),
                            if (a != null)
                              CustomPaint(
                                painter: _LandmarkPainter(analysis: a),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ListTile(
                      title: const Text('Pipeline'),
                      subtitle: Text(
                        a == null
                            ? 'in attesa della prima analisi…'
                            : 'analisi: ${_fps.toStringAsFixed(1)} fps · '
                                'inferenza: ${a.inferenceTimeMs} ms\n'
                                'volto: ${a.faceDetected} · '
                                'posa: ${a.poseDetected}',
                      ),
                    ),
                    ListTile(
                      title: const Text('Metriche derivate (EMA)'),
                      subtitle: Text(
                        s == null
                            ? 'nessun campione ancora'
                            : 'tensione: ${s.facialTension.toStringAsFixed(2)} '
                                '· postura: ${s.postureScore.toStringAsFixed(2)}\n'
                                'hr: ${s.hr?.toStringAsFixed(1) ?? '— (Fase 3)'} '
                                '· quality: ${s.hrQuality.toStringAsFixed(2)}',
                      ),
                    ),
                    if (a != null && a.blendshapes.isNotEmpty)
                      ListTile(
                        title: const Text('Blendshapes chiave'),
                        subtitle: Text(
                          <String>[
                            'browDownLeft', 'browDownRight',
                            'eyeSquintLeft', 'eyeSquintRight',
                            'mouthPressLeft', 'mouthPressRight',
                          ]
                              .map((String k) =>
                                  '$k: ${(a.blendshapes[k] ?? 0).toStringAsFixed(2)}')
                              .join('\n'),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// Disegna i landmark normalizzati sopra la preview. La preview della
/// camera frontale è specchiata da Flutter, quindi specchiamo la x.
class _LandmarkPainter extends CustomPainter {
  _LandmarkPainter({required this.analysis});

  final FrameAnalysis analysis;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint facePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final Paint posePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    void drawFlat(List<double> flat, Paint paint) {
      final List<Offset> points = <Offset>[
        for (int i = 0; i + 1 < flat.length; i += 2)
          Offset((1 - flat[i]) * size.width, flat[i + 1] * size.height),
      ];
      canvas.drawPoints(PointMode.points, points, paint);
    }

    drawFlat(analysis.faceLandmarks, facePaint);
    drawFlat(analysis.poseLandmarks, posePaint);
  }

  @override
  bool shouldRepaint(_LandmarkPainter oldDelegate) =>
      oldDelegate.analysis != analysis;
}
```

Note: `PointMode` requires `import 'dart:ui' show PointMode;`. If `AppColors`/`AppRadius` names differ in `app_tokens.dart`, use the existing token names (check the file; do not invent new tokens).

- [ ] **Step 2: Add the route**

In `lib/core/routing/app_router.dart`:

```dart
  static const String debugSensing = '/debug/sensing';
```

and in the switch:

```dart
      AppRoutes.debugSensing => (_) => const SensingDebugScreen(),
```

with import `import '../../features/debug/sensing_debug_screen.dart';`.

- [ ] **Step 3: Add the entry point in the debug menu**

In `lib/features/debug/debug_screen.dart`, replace the stale `SwitchListTile` (subtitle «CameraSensingSource arriva in Fase 2») with:

```dart
          SwitchListTile(
            value: true,
            onChanged: null,
            title: const Text('Sorgente simulata'),
            subtitle: const Text(
              'Lo switch sim/reale per la sessione arriva in Fase 4',
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.android)
            ListTile(
              title: const Text('Sensing camera (Fase 2)'),
              subtitle: const Text(
                'Preview + landmark MediaPipe + metriche grezze',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.debugSensing),
            ),
```

with imports `import 'package:flutter/foundation.dart';` and `import '../../core/routing/app_router.dart';`.

- [ ] **Step 4: Verify tests, analyzer, build**

```bash
flutter test && flutter analyze && flutter build apk --debug
```

Expected: all tests PASS, `No issues found!`, APK built.

- [ ] **Step 5: Commit**

```bash
git add lib/features/debug/ lib/core/routing/app_router.dart
git commit -m "feat: add hidden sensing debug screen with landmark overlay"
```

---

### Task 6: Manual verification on device + decision log

**Files:**
- Modify: `docs/decisions.md` (create if missing)

- [ ] **Step 1: Manual verification on an Android device/emulator (front camera needed — physical device strongly preferred)**

```bash
flutter run -d <android-device-id>
```

Checklist (all must hold):
1. Home → long-press title → Debug → «Sensing camera (Fase 2)».
2. First open asks the CAMERA permission (camera plugin requests it); grant.
3. Preview shows; blue face points and orange pose points track your face/shoulders.
4. FPS ~3–5, inference time displayed and stable (< 150 ms on a mid-range device).
5. Frown/squint → «tensione» raises; relax → decays smoothly (EMA).
6. Slouch toward the desk → «postura» drops; sit up → recovers.
7. Cover the camera → no crash; metrics drift back toward rest values.
8. Leave the screen → camera light turns off (source disposed).
9. Regular session flow (Home → Calibrazione → Sessione) still works entirely on the simulator, camera never activates.

- [ ] **Step 2: Record decisions**

Append to `docs/decisions.md`:

```markdown
## Fase 2 — Camera + MediaPipe landmark (Android)

- **Frames cross the Dart→Kotlin channel, never the reverse.** The camera
  plugin owns capture (per CLAUDE.md); MediaPipe runs natively. YUV planes
  are passed in-process to Kotlin and the channel returns only landmarks
  and blendshapes. No frame is stored, encoded or transmitted (NFR1/NFR2).
- **Models bundled in Android assets** (face_landmarker.task,
  pose_landmarker_lite.task): no runtime download keeps the app
  network-free (NFR1).
- **VIDEO running mode + serial background TaskQueue + ~5 fps throttling
  with frame dropping**: bounded battery/CPU cost; landmark cadence is far
  above what the classifier needs (1 Hz samples).
- **Missing signal falls back to rest values** (no face/pose → tension
  0.15, posture 0.9 targets via EMA): absence of signal must never push
  the classifier toward ALTO (NFR3, conservative-thresholds principle).
- **Session flow untouched**: `sensingSourceProvider` still returns the
  simulator; the camera pipeline is reachable only from the hidden debug
  screen. The sim/real switch lands in Fase 4 as planned.
```

- [ ] **Step 3: Commit**

```bash
git add docs/decisions.md
git commit -m "docs: record Fase 2 sensing pipeline decisions"
```

---

## Self-Review (done at planning time)

- **Spec coverage:** Fase 2 DoD = «segnali visivi (tensione, postura) reali e stabili sulla debug screen Android» → Tasks 2–5; «nessun impatto sul flusso utente» → provider untouched, verified in Task 6 step 1.9; «schermata debug nascosta con overlay dei landmark, FPS, valori grezzi» → Task 5.
- **Placeholder scan:** none — all code shown in full.
- **Type consistency:** `FramePacket`/`FrameAnalysis` field names match across pigeon def, Kotlin usage, Dart usage; `VisualSampleAggregator.add/snapshot` consistent between Task 4 code and tests; `AppRoutes.debugSensing` consistent between Task 5 steps. One deliberate flexibility note: generated Pigeon/Kotlin signatures may differ slightly by version — the plan instructs adapting hand-written code to generated code, never the reverse.
