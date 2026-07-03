import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import '../../data/pause_types.dart';

enum _BreathPhase { prepare, inhale, hold, exhale }

/// Respirazione 4-7-8: cerchio doppio animato espandi/contrai sincronizzato
/// col countdown (mono) + barra di avanzamento dei cicli. ~4 cicli ≈ 80 s.
class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});

  static const int totalCycles = 4;

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> {
  static const Map<_BreathPhase, int> _phaseSeconds = <_BreathPhase, int>{
    _BreathPhase.prepare: 3,
    _BreathPhase.inhale: 4,
    _BreathPhase.hold: 7,
    _BreathPhase.exhale: 8,
  };

  _BreathPhase _phase = _BreathPhase.prepare;
  int _secondsLeft = 3;
  int _cycle = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (_secondsLeft > 1) {
      setState(() => _secondsLeft--);
      return;
    }
    // Fase conclusa → successiva.
    switch (_phase) {
      case _BreathPhase.prepare:
        _enter(_BreathPhase.inhale);
      case _BreathPhase.inhale:
        _enter(_BreathPhase.hold);
      case _BreathPhase.hold:
        _enter(_BreathPhase.exhale);
      case _BreathPhase.exhale:
        if (_cycle + 1 >= BreathingScreen.totalCycles) {
          _timer?.cancel();
          unawaited(
            Navigator.of(context).pushReplacementNamed(
              AppRoutes.pauseDone,
              arguments: PauseKind.breathing,
            ),
          );
          return;
        }
        setState(() => _cycle++);
        _enter(_BreathPhase.inhale);
    }
  }

  void _enter(_BreathPhase phase) {
    setState(() {
      _phase = phase;
      _secondsLeft = _phaseSeconds[phase]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String label = switch (_phase) {
      _BreathPhase.prepare => context.l10n.breathingGetReady,
      _BreathPhase.inhale => context.l10n.breathingIn,
      _BreathPhase.hold => context.l10n.breathingHold,
      _BreathPhase.exhale => context.l10n.breathingOut,
    };
    // Cerchio interno: espanso in inspirazione/hold, contratto in
    // espirazione; l'animazione dura quanto la fase (sincronizzata).
    final double scale = switch (_phase) {
      _BreathPhase.prepare => 0.55,
      _BreathPhase.inhale || _BreathPhase.hold => 1.0,
      _BreathPhase.exhale => 0.55,
    };
    final Duration phaseDuration =
        Duration(seconds: _phaseSeconds[_phase]!);
    final double cycleProgress = _cycle / BreathingScreen.totalCycles;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pauseBreathingTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: <Widget>[
              const Spacer(),
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // Cerchio esterno fisso: il riferimento «polmoni pieni».
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                    ),
                    AnimatedScale(
                      scale: scale,
                      duration: _phase == _BreathPhase.hold
                          ? Duration.zero
                          : phaseDuration,
                      curve: Curves.easeInOut,
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '$_secondsLeft',
                          style:
                              AppTheme.timerStyle.copyWith(fontSize: 56),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                context.l10n.breathingCycle(
                  (_cycle + 1).clamp(1, BreathingScreen.totalCycles),
                  BreathingScreen.totalCycles,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: cycleProgress,
                minHeight: AppSpacing.sm,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
