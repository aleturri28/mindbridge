import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/util/l10n_ext.dart';

/// Scelta dell'utente sulla proposta di pausa (FR4: sempre proposta,
/// mai imposta).
enum StressAlertChoice { pause, snooze, ignore }

/// Bottom sheet asimmetrico della notifica di stress (dal medium-fi):
/// «PAUSA GUIDATA» primario largo, «Posticipa 20 min» e «Ignora» outline
/// stretti. Chiusura senza scelta = Ignora.
class StressAlertSheet extends StatelessWidget {
  const StressAlertSheet({super.key});

  static Future<StressAlertChoice> show(BuildContext context) async {
    final StressAlertChoice? choice =
        await showModalBottomSheet<StressAlertChoice>(
      context: context,
      builder: (_) => const StressAlertSheet(),
    );
    return choice ?? StressAlertChoice.ignore;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.spa_outlined, color: AppColors.stressMedium),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    context.l10n.alertTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.alertBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(StressAlertChoice.pause),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(context.l10n.alertPauseCta),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(StressAlertChoice.snooze),
                    child: Text(context.l10n.alertSnooze),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(StressAlertChoice.ignore),
                    child: Text(context.l10n.alertIgnore),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
