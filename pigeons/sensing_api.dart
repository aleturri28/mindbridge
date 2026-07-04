import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/sensing/camera/sensing_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/it/unitn/mindbridge/SensingApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'it.unitn.mindbridge'),
    dartPackageName: 'mindbridge',
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
