import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import 'session_controller.dart';

/// Calibrazione (FR8): elenca esplicitamente i segnali rilevati e il perché
/// (correzione dalla heuristic evaluation), poi ~60 s di raccolta a riposo.
class CalibrationScreen extends ConsumerWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SessionState>(sessionControllerProvider,
        (SessionState? previous, SessionState next) {
      if (previous?.phase == SessionPhase.calibrating &&
          next.phase == SessionPhase.calibrated) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.session);
      }
    });

    final SessionState state = ref.watch(sessionControllerProvider);
    final bool calibrating = state.phase == SessionPhase.calibrating;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.calibrationTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: calibrating
              ? _CalibrationProgress(state: state)
              : _CalibrationIntro(
                  onStart: () => ref
                      .read(sessionControllerProvider.notifier)
                      .startCalibration(),
                ),
        ),
      ),
    );
  }
}

class _CalibrationIntro extends StatelessWidget {
  const _CalibrationIntro({required this.onStart});

  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.l10n.calibrationIntro,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.calibrationSignalsTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Column(
            children: <Widget>[
              _SignalTile(
                icon: Icons.favorite_outline,
                text: context.l10n.calibrationSignalHr,
              ),
              _SignalTile(
                icon: Icons.face_outlined,
                text: context.l10n.calibrationSignalTension,
              ),
              _SignalTile(
                icon: Icons.accessibility_new_outlined,
                text: context.l10n.calibrationSignalPosture,
              ),
            ],
          ),
        ),
        const Spacer(),
        FilledButton(
          onPressed: onStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(context.l10n.calibrationStart),
          ),
        ),
      ],
    );
  }
}

class _CalibrationProgress extends StatelessWidget {
  const _CalibrationProgress({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final int total = SessionController.calibrationDuration.inSeconds;
    final double progress = 1 - state.calibrationSecondsLeft / total;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: <Widget>[
              CircularProgressIndicator(
                value: progress,
                strokeWidth: AppSpacing.sm,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              ),
              Center(
                child: Text(
                  '${state.calibrationSecondsLeft}',
                  style: AppTheme.timerStyle.copyWith(fontSize: 48),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.calibrationInProgress,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.calibrationSecondsLeft(state.calibrationSecondsLeft),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(text),
    );
  }
}
