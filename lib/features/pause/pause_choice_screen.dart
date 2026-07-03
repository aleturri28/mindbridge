import 'package:flutter/material.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import '../../data/pause_types.dart';

/// Scelta pausa: 3 card con stato selezionato ben visibile (correzione
/// dalla heuristic evaluation). Pause ≤ 5 minuti.
class PauseChoiceScreen extends StatefulWidget {
  const PauseChoiceScreen({super.key});

  @override
  State<PauseChoiceScreen> createState() => _PauseChoiceScreenState();
}

class _PauseChoiceScreenState extends State<PauseChoiceScreen> {
  PauseKind? _selected;

  static const Map<PauseKind, String> _routes = <PauseKind, String>{
    PauseKind.breathing: AppRoutes.pauseBreathing,
    PauseKind.stretching: AppRoutes.pauseStretching,
    PauseKind.music: AppRoutes.pauseMusic,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pauseChoiceTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.l10n.pauseChoiceSubtitle,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              _PauseCard(
                kind: PauseKind.breathing,
                icon: Icons.air,
                title: context.l10n.pauseBreathingTitle,
                subtitle: context.l10n.pauseBreathingSubtitle,
                selected: _selected == PauseKind.breathing,
                onTap: () =>
                    setState(() => _selected = PauseKind.breathing),
              ),
              const SizedBox(height: AppSpacing.md),
              _PauseCard(
                kind: PauseKind.stretching,
                icon: Icons.accessibility_new,
                title: context.l10n.pauseStretchingTitle,
                subtitle: context.l10n.pauseStretchingSubtitle,
                selected: _selected == PauseKind.stretching,
                onTap: () =>
                    setState(() => _selected = PauseKind.stretching),
              ),
              const SizedBox(height: AppSpacing.md),
              _PauseCard(
                kind: PauseKind.music,
                icon: Icons.music_note_outlined,
                title: context.l10n.pauseMusicTitle,
                subtitle: context.l10n.pauseMusicSubtitle,
                selected: _selected == PauseKind.music,
                onTap: () => setState(() => _selected = PauseKind.music),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _selected == null
                    ? null
                    : () => Navigator.of(context)
                        .pushReplacementNamed(_routes[_selected]!),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(context.l10n.pauseStart),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseCard extends StatelessWidget {
  const _PauseCard({
    required this.kind,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final PauseKind kind;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      // Stato selezionato: bordo primario + sfondo tinto, non solo colore
      // (c'è anche l'icona di spunta).
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      color: selected
          ? AppColors.primary.withValues(alpha: 0.08)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 40, color: AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
