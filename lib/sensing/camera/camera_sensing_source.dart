import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    final double tension = facialTensionFromBlendshapes(analysis.blendshapes);
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
