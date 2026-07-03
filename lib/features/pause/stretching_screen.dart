import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import '../../data/pause_types.dart';

class _StretchStep {
  const _StretchStep(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

/// Stretching guidato da seduti: 4 esercizi × 45 s (≤ 5 min totali).
class StretchingScreen extends StatefulWidget {
  const StretchingScreen({super.key});

  static const int secondsPerStep = 45;

  @override
  State<StretchingScreen> createState() => _StretchingScreenState();
}

class _StretchingScreenState extends State<StretchingScreen> {
  int _step = 0;
  int _secondsLeft = StretchingScreen.secondsPerStep;
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

  List<_StretchStep> _steps(BuildContext context) => <_StretchStep>[
        _StretchStep(
          Icons.face_retouching_natural,
          context.l10n.stretchingNeckTitle,
          context.l10n.stretchingNeckBody,
        ),
        _StretchStep(
          Icons.airline_seat_recline_normal,
          context.l10n.stretchingShouldersTitle,
          context.l10n.stretchingShouldersBody,
        ),
        _StretchStep(
          Icons.self_improvement,
          context.l10n.stretchingBackTitle,
          context.l10n.stretchingBackBody,
        ),
        _StretchStep(
          Icons.back_hand_outlined,
          context.l10n.stretchingWristsTitle,
          context.l10n.stretchingWristsBody,
        ),
      ];

  void _tick() {
    if (_secondsLeft > 1) {
      setState(() => _secondsLeft--);
    } else {
      _next();
    }
  }

  void _next() {
    if (_step + 1 >= _steps(context).length) {
      _timer?.cancel();
      unawaited(
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.pauseDone,
          arguments: PauseKind.stretching,
        ),
      );
      return;
    }
    setState(() {
      _step++;
      _secondsLeft = StretchingScreen.secondsPerStep;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<_StretchStep> steps = _steps(context);
    final _StretchStep current = steps[_step];
    final double progress =
        1 - _secondsLeft / StretchingScreen.secondsPerStep;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pauseStretchingTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.l10n.stretchingStep(_step + 1, steps.length),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: AppSpacing.sm,
                        color: AppColors.primary,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                      ),
                      Center(
                        child:
                            Icon(current.icon, size: 72, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                current.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                current.body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  '$_secondsLeft',
                  style: AppTheme.timerStyle.copyWith(fontSize: 40),
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _next,
                child: Text(context.l10n.next),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
