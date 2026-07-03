import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../classifier/baseline.dart';
import '../../classifier/stress_classifier.dart';
import '../../classifier/stress_level.dart';
import '../../core/providers.dart';
import '../../core/services/session_foreground_service.dart';
import '../../data/pause_types.dart';
import '../../sensing/sensing_sample.dart';
import '../../sensing/sensing_source.dart';

enum SessionPhase {
  idle,
  calibrating,

  /// Calibrazione appena conclusa: la UI naviga alla sessione.
  calibrated,
  running,
  suspended,

  /// Micro-pausa in corso (respirazione/stretching/musica).
  inBreak,
}

@immutable
class SessionState {
  const SessionState({
    required this.phase,
    required this.level,
    required this.elapsed,
    required this.stressAlert,
    required this.calibrationSecondsLeft,
  });

  static const SessionState initial = SessionState(
    phase: SessionPhase.idle,
    level: StressLevel.basso,
    elapsed: Duration.zero,
    stressAlert: false,
    calibrationSecondsLeft: 0,
  );

  final SessionPhase phase;

  /// Solo etichetta (NFR10): la UI non vede mai score o bpm.
  final StressLevel level;
  final Duration elapsed;

  /// True quando va proposta una pausa: la UI mostra il bottom sheet e
  /// risponde con accept/snooze/ignore.
  final bool stressAlert;
  final int calibrationSecondsLeft;

  SessionState copyWith({
    SessionPhase? phase,
    StressLevel? level,
    Duration? elapsed,
    bool? stressAlert,
    int? calibrationSecondsLeft,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      level: level ?? this.level,
      elapsed: elapsed ?? this.elapsed,
      stressAlert: stressAlert ?? this.stressAlert,
      calibrationSecondsLeft:
          calibrationSecondsLeft ?? this.calibrationSecondsLeft,
    );
  }
}

final NotifierProvider<SessionController, SessionState>
    sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Orchestratore della sessione: sensing → classifier → stato UI +
/// persistenza. Il flusso di notifica resta nella UI (che ha l10n/context).
class SessionController extends Notifier<SessionState> {
  static const Duration calibrationDuration = Duration(seconds: 60);
  static const Duration _samplePersistInterval = Duration(seconds: 10);
  static const Duration snoozeDuration = Duration(minutes: 20);

  StreamSubscription<SensingSample>? _subscription;
  StressClassifier? _classifier;
  Timer? _ticker;
  Timer? _calibrationTimer;
  int? _sessionId;
  DateTime? _lastPersistedAt;
  Duration _accumulated = Duration.zero;
  DateTime? _resumedAt;
  final List<SensingSample> _calibrationSamples = <SensingSample>[];

  @override
  SessionState build() {
    ref.onDispose(() => unawaited(_teardown()));
    return SessionState.initial;
  }

  SensingSource get _source => ref.read(sensingSourceProvider);

  /// Calibrazione FR8: ~60 s di campioni a riposo → baseline personale.
  Future<void> startCalibration() async {
    if (state.phase == SessionPhase.calibrating) {
      return;
    }
    await _teardown();
    _calibrationSamples.clear();
    state = SessionState.initial.copyWith(
      phase: SessionPhase.calibrating,
      calibrationSecondsLeft: calibrationDuration.inSeconds,
    );
    _subscription = _source.signals.listen(_calibrationSamples.add);
    await _source.start();

    final DateTime end = DateTime.now().add(calibrationDuration);
    _calibrationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) async {
        final int left = end.difference(DateTime.now()).inSeconds;
        if (left > 0) {
          state = state.copyWith(calibrationSecondsLeft: left);
          return;
        }
        timer.cancel();
        await _subscription?.cancel();
        _subscription = null;
        await _source.stop();
        if (_calibrationSamples.isNotEmpty) {
          await ref
              .read(preferencesProvider)
              .setBaseline(Baseline.fromSamples(_calibrationSamples));
        }
        state = state.copyWith(
          phase: SessionPhase.calibrated,
          calibrationSecondsLeft: 0,
        );
      },
    );
  }

  /// [foregroundTitle]/[foregroundBody]: testi (l10n, passati dalla UI)
  /// per la notifica persistente Android di sessione attiva.
  Future<void> startSession({
    String? foregroundTitle,
    String? foregroundBody,
  }) async {
    if (state.phase == SessionPhase.running) {
      return;
    }
    final Baseline? baseline = ref.read(preferencesProvider).baseline;
    if (baseline == null) {
      return;
    }
    await _teardown();
    _classifier = StressClassifier(baseline: baseline);
    _sessionId = await ref.read(sessionRepositoryProvider).startSession();
    _lastPersistedAt = null;
    _accumulated = Duration.zero;
    _resumedAt = DateTime.now();

    _subscription = _source.signals.listen(_onSample);
    await _source.start();
    await WakelockPlus.enable();
    if (foregroundTitle != null && foregroundBody != null) {
      await SessionForegroundService.start(
        title: foregroundTitle,
        body: foregroundBody,
      );
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    state = SessionState.initial.copyWith(phase: SessionPhase.running);
  }

  void _tick() {
    if (_resumedAt == null) {
      return;
    }
    state = state.copyWith(
      elapsed: _accumulated + DateTime.now().difference(_resumedAt!),
    );
  }

  void _onSample(SensingSample sample) {
    final StressClassifier? classifier = _classifier;
    final int? sessionId = _sessionId;
    if (classifier == null || sessionId == null) {
      return;
    }
    // In pausa o sospesi non si classifica (la sorgente è comunque ferma
    // durante la sospensione).
    if (state.phase != SessionPhase.running) {
      return;
    }
    final ClassifierOutput out = classifier.process(sample);
    if (_lastPersistedAt == null ||
        sample.timestamp.difference(_lastPersistedAt!) >=
            _samplePersistInterval) {
      _lastPersistedAt = sample.timestamp;
      unawaited(
        ref
            .read(sessionRepositoryProvider)
            .addSample(sessionId, out.level, sample.timestamp),
      );
    }
    state = state.copyWith(
      level: out.level,
      stressAlert: state.stressAlert || out.shouldNotify,
    );
  }

  Future<void> suspend() async {
    if (state.phase != SessionPhase.running) {
      return;
    }
    _accumulated += DateTime.now().difference(_resumedAt!);
    _resumedAt = null;
    await _source.stop();
    state = state.copyWith(phase: SessionPhase.suspended);
  }

  Future<void> resume() async {
    if (state.phase != SessionPhase.suspended) {
      return;
    }
    _resumedAt = DateTime.now();
    await _source.start();
    state = state.copyWith(phase: SessionPhase.running);
  }

  Future<void> stopSession() async {
    final int? sessionId = _sessionId;
    await _teardown();
    if (sessionId != null) {
      await ref.read(sessionRepositoryProvider).endSession(sessionId);
    }
    state = SessionState.initial;
  }

  /// FR4: «PAUSA GUIDATA» — la registrazione (kind + accepted) avviene
  /// al completamento della pausa, quando il tipo è noto.
  void acceptPause() {
    state = state.copyWith(phase: SessionPhase.inBreak, stressAlert: false);
  }

  /// FR4: «Posticipa 20 min».
  void snoozePause() {
    _classifier?.notifySnoozed(snoozeDuration);
    _recordPause(PauseOutcome.snoozed);
    state = state.copyWith(stressAlert: false);
  }

  /// FR4: «Ignora» (il cooldown del classifier evita il martellamento).
  void ignorePause() {
    _recordPause(PauseOutcome.ignored);
    state = state.copyWith(stressAlert: false);
  }

  /// Fine micro-pausa («RIPRENDI LO STUDIO»).
  void completeBreak(PauseKind kind) {
    _recordPause(PauseOutcome.accepted, kind: kind, completed: true);
    if (state.phase == SessionPhase.inBreak) {
      state = state.copyWith(phase: SessionPhase.running);
    }
  }

  void _recordPause(
    PauseOutcome outcome, {
    PauseKind? kind,
    bool completed = false,
  }) {
    final int? sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }
    unawaited(
      ref.read(sessionRepositoryProvider).addPause(
            sessionId,
            outcome,
            kind: kind,
            completed: completed,
          ),
    );
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    _calibrationTimer?.cancel();
    _calibrationTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _source.stop();
    _classifier = null;
    _sessionId = null;
    _resumedAt = null;
    _accumulated = Duration.zero;
    await WakelockPlus.disable();
    await SessionForegroundService.stop();
  }
}
