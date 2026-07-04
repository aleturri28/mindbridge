import 'dart:async';
import 'dart:ui' show PointMode;

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
                        borderRadius: BorderRadius.circular(AppRadii.card),
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
                            'browDownLeft',
                            'browDownRight',
                            'eyeSquintLeft',
                            'eyeSquintRight',
                            'mouthPressLeft',
                            'mouthPressRight',
                          ]
                              .map((String k) => '$k: '
                                  '${(a.blendshapes[k] ?? 0).toStringAsFixed(2)}')
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
      ..color = AppColors.stressMedium
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
