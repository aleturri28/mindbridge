import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../classifier/stress_level.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import 'session_controller.dart';
import 'widgets/stress_alert_sheet.dart';
import 'widgets/stress_donut.dart';

/// Sessione in corso: donut colorato + etichetta (mai numeri, NFR10),
/// timer mono, Sospendi/Riprendi e Stop differenziato in Alert.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.ensurePermissions();
      if (!mounted) {
        return;
      }
      await ref.read(sessionControllerProvider.notifier).startSession(
            foregroundTitle: context.l10n.sessionForegroundTitle,
            foregroundBody: context.l10n.sessionForegroundBody,
          );
    });
  }

  Future<void> _onStressAlert() async {
    // NFR4: avviso discreto (vibrazione di default) + bottom sheet.
    final prefs = ref.read(preferencesProvider);
    await NotificationService.showStressAlert(
      title: context.l10n.alertTitle,
      body: context.l10n.alertBody,
      mode: prefs.notificationMode,
      libraryMode: prefs.libraryMode,
    );
    if (!mounted) {
      return;
    }
    final StressAlertChoice choice = await StressAlertSheet.show(context);
    if (!mounted) {
      return;
    }
    final SessionController controller =
        ref.read(sessionControllerProvider.notifier);
    switch (choice) {
      case StressAlertChoice.pause:
        controller.acceptPause();
        await Navigator.of(context).pushNamed(AppRoutes.pauseChoice);
      case StressAlertChoice.snooze:
        controller.snoozePause();
      case StressAlertChoice.ignore:
        controller.ignorePause();
    }
  }

  Future<void> _confirmStop() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.sessionStopConfirmTitle),
        content: Text(context.l10n.sessionStopConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.stressHigh),
            child: Text(context.l10n.sessionStopConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(sessionControllerProvider.notifier).stopSession();
    if (mounted) {
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider,
        (SessionState? previous, SessionState next) {
      if (next.stressAlert && !(previous?.stressAlert ?? false)) {
        // NFR9: mostrata subito dopo il riconoscimento (<2 s).
        Future<void>.microtask(_onStressAlert);
      }
    });

    final SessionState state = ref.watch(sessionControllerProvider);
    final StressColors stressColors =
        Theme.of(context).extension<StressColors>()!;
    final bool suspended = state.phase == SessionPhase.suspended;
    final (Color levelColor, String levelLabel) = switch (state.level) {
      StressLevel.basso => (stressColors.low, context.l10n.stressLow),
      StressLevel.medio => (stressColors.medium, context.l10n.stressMedium),
      StressLevel.alto => (stressColors.high, context.l10n.stressHigh),
    };

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          suspended
              ? context.l10n.sessionSuspendedTitle
              : context.l10n.sessionTitle,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Chip(
                  avatar: const Icon(Icons.science_outlined, size: 18),
                  label: Text(context.l10n.sessionSimulatedBadge),
                ),
              ),
              const Spacer(),
              Text(
                context.l10n.sessionYourState,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Opacity(
                  opacity: suspended ? 0.4 : 1,
                  child:
                      StressDonut(color: levelColor, label: levelLabel),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _format(state.elapsed),
                textAlign: TextAlign.center,
                style: AppTheme.timerStyle.copyWith(fontSize: 48),
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final SessionController controller =
                            ref.read(sessionControllerProvider.notifier);
                        if (suspended) {
                          await controller.resume();
                        } else {
                          await controller.suspend();
                        }
                      },
                      icon: Icon(
                          suspended ? Icons.play_arrow : Icons.pause),
                      label: Text(
                        suspended
                            ? context.l10n.sessionResume
                            : context.l10n.sessionSuspend,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    // Correzione heuristic evaluation: Stop differenziato
                    // con il colore Alert.
                    child: FilledButton.icon(
                      onPressed: _confirmStop,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.stressHigh,
                      ),
                      icon: const Icon(Icons.stop),
                      label: Text(context.l10n.sessionStop),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final int hours = d.inHours;
    final String minutes = two(d.inMinutes.remainder(60));
    final String seconds = two(d.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
