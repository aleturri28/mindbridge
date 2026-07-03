import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import '../../data/pause_types.dart';
import '../session/session_controller.dart';

/// Pausa completata: header verde, «RIPRENDI LO STUDIO» primario che
/// registra la pausa (accettata + completata) e torna alla sessione.
class PauseDoneScreen extends ConsumerWidget {
  const PauseDoneScreen({super.key, required this.kind});

  final PauseKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: AppColors.stressLow,
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + AppSpacing.xl,
              bottom: AppSpacing.xl,
            ),
            child: Column(
              children: <Widget>[
                const Icon(
                  Icons.check_circle_outline,
                  size: 96,
                  color: Colors.white,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.pauseDoneTitle,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Spacer(),
                  Text(
                    context.l10n.pauseDoneBody,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(sessionControllerProvider.notifier)
                          .completeBreak(kind);
                      Navigator.of(context).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(context.l10n.pauseDoneResume),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
