import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../rppg/roi_extractor.dart';
import '../rppg/rppg_config.dart';
import '../rppg/rppg_isolate.dart';
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

  /// Stime HR recenti (bpm, qualità, istante) sopra il pavimento anti-rumore,
  /// entro [RppgConfig.hrConsistencyWindow]. L'affidabilità dell'HR nasce dal
  /// loro accordo, non da una singola purezza spettrale.
  final List<({double bpm, double quality, DateTime at})> _recentHr =
      <({double bpm, double quality, DateTime at})>[];

  void add(FrameAnalysis analysis) {
    final double tension = facialTensionFromBlendshapes(analysis.blendshapes);
    final double posture = postureScoreFromPose(analysis.poseLandmarks);
    _tension = _ema(_tension, tension);
    _posture = _ema(_posture, posture);
  }

  /// Registra l'ultima stima rPPG. Le stime sotto [RppgConfig.qualityThreshold]
  /// (pavimento anti-rumore) vengono ignorate; le altre entrano nello storico
  /// recente, che [snapshot] valuta per consistenza. [now] è iniettabile nei
  /// test; di default l'orario reale.
  void updateHr(RppgEstimate estimate, {DateTime? now}) {
    if (estimate.quality < RppgConfig.qualityThreshold) {
      return;
    }
    final DateTime at = now ?? DateTime.now();
    _recentHr.add((bpm: estimate.hrBpm, quality: estimate.quality, at: at));
  }

  double _ema(double previous, double next) =>
      previous + alpha * (next - previous);

  /// Campione corrente. L'HR è mostrato solo se affidabile: servono almeno
  /// [RppgConfig.minConsistentEstimates] stime recenti (entro
  /// [RppgConfig.hrConsistencyWindow]) che concordano — cioè almeno altrettante
  /// entro [RppgConfig.maxHrSpreadBpm] dalla loro mediana. In tal caso hr = la
  /// mediana (robusta ai picchi occasionali); altrimenti hr null e quality 0.
  /// Rumore e movimento producono stime sparpagliate → non affidabili → hr
  /// nascosto: degradazione onesta, mai un valore inventato (NFR3/NFR10).
  SensingSample snapshot(DateTime now) {
    _recentHr.removeWhere((({double bpm, double quality, DateTime at}) e) =>
        now.difference(e.at) > RppgConfig.hrConsistencyWindow);

    double? hr;
    double hrQuality = 0;
    if (_recentHr.length >= RppgConfig.minConsistentEstimates) {
      final List<double> bpms = <double>[
        for (final ({double bpm, double quality, DateTime at}) e in _recentHr)
          e.bpm,
      ]..sort();
      final double median = bpms[bpms.length ~/ 2];
      final int inliers = bpms
          .where((double b) => (b - median).abs() <= RppgConfig.maxHrSpreadBpm)
          .length;
      if (inliers >= RppgConfig.minConsistentEstimates) {
        hr = median;
        hrQuality = _recentHr.last.quality;
      }
    }

    return SensingSample(
      hr: hr,
      hrQuality: hrQuality,
      facialTension: _tension,
      postureScore: _posture,
      timestamp: now,
    );
  }
}

/// Sorgente reale (Fase 2+3, Android): camera frontale a bassa risoluzione →
/// canale Pigeon → MediaPipe nativo → metriche visive, più estrazione ROI
/// per rPPG su ogni frame nativo. I frame non lasciano mai il processo
/// (NFR1/NFR2).
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

  /// Stime rPPG grezze inoltrate per la debug screen (validazione manuale).
  /// Controller stabile, sottoscrivibile prima di [start] (a differenza dello
  /// stream del processor, che nasce solo allo spawn).
  final StreamController<RppgEstimate> _rawEstimates =
      StreamController<RppgEstimate>.broadcast();

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

  /// Istante dell'ultima [FrameAnalysis] con volto rilevato. Le analisi
  /// transitorie senza volto NON svuotano [_lastFaceLandmarks] (di proposito:
  /// tollera perdite momentanee di tracking), ma un'assenza prolungata oltre
  /// [RppgConfig.estimateStaleAfter] rende il poligono cache stale — va
  /// ignorato invece di continuare a campionare una ROI ormai non valida.
  DateTime? _lastFaceSeenAt;

  /// Diagnostica (debug screen): conteggio frame ROI inviati all'isolate e
  /// ultimo pixelCount della ROI. Servono a localizzare uno stallo della
  /// pipeline durante la validazione manuale (nessun impatto sul flusso).
  int _rppgFramesSent = 0;
  int _lastPixelCount = -1;

  /// Frame ROI (con pixelCount>0) inoltrati finora all'isolate rPPG.
  int get rppgFramesSent => _rppgFramesSent;

  /// pixelCount dell'ultima estrazione ROI tentata (-1 = mai tentata,
  /// 0 = ROI vuota/fuori frame).
  int get lastRoiPixelCount => _lastPixelCount;

  @override
  Stream<SensingSample> get signals => _samples.stream;

  /// Analisi grezze per la debug screen (overlay landmark, FPS).
  Stream<FrameAnalysis> get analyses => _analyses.stream;

  /// Stime rPPG grezze (NON gated da qualità/staleness): solo per la debug
  /// screen, per confrontare il bpm calcolato col riferimento durante la
  /// validazione manuale. Il flusso utente usa sempre [signals], dove hr è
  /// null finché non è affidabile (NFR3).
  Stream<RppgEstimate> get rawEstimates => _rawEstimates.stream;

  /// Controller esposto per `CameraPreview` nella debug screen.
  CameraController? get controller => _controller;

  @override
  Future<void> start() async {
    if (_controller != null) {
      return;
    }
    await _hostApi.initialize();
    _rppgProcessor = await RppgProcessor.spawn();
    _rppgSub = _rppgProcessor!.estimates.listen((RppgEstimate estimate) {
      _aggregator.updateHr(estimate);
      if (!_rawEstimates.isClosed) {
        _rawEstimates.add(estimate);
      }
    });

    final List<CameraDescription> cameras = await availableCameras();
    final CameraDescription front = cameras.firstWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _sensorOrientation = front.sensorOrientation;

    // ResolutionPreset.medium (non low): più pixel nella ROI fronte/guance
    // → il rumore di quantizzazione si media meglio (∝ 1/√N) → SNR del polso
    // più alto, quality rPPG più alta e meno picchi spuri. Costo CPU/batteria
    // contenuto; l'analisi landmark resta throttled a ~5fps.
    final CameraController controller = CameraController(
      front,
      ResolutionPreset.medium,
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
    final DateTime? lastSeen = _lastFaceSeenAt;
    final bool cacheStale = lastSeen == null ||
        DateTime.now().difference(lastSeen) > RppgConfig.estimateStaleAfter;
    if (processor == null || _lastFaceLandmarks.isEmpty || cacheStale) {
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
    _lastPixelCount = means.pixelCount;
    if (means.pixelCount == 0) {
      return;
    }
    _rppgFramesSent++;
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
          _lastFaceSeenAt = now;
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
    _lastFaceSeenAt = null;
    _rppgFramesSent = 0;
    _lastPixelCount = -1;
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
    unawaited(_rawEstimates.close());
  }
}
