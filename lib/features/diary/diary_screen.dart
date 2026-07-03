import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../classifier/stress_level.dart';
import '../../core/providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import '../../data/repositories/diary_repository.dart';
import '../../data/repositories/session_repository.dart';
import 'widgets/stress_bar_chart.dart';

final StreamProvider<List<DayStress>> _weekStressProvider =
    StreamProvider<List<DayStress>>(
  (Ref ref) =>
      ref.watch(diaryRepositoryProvider).watchWeek(DateTime.now()),
);

final StreamProvider<WeekPauseStats> _weekPausesProvider =
    StreamProvider<WeekPauseStats>(
  (Ref ref) =>
      ref.watch(diaryRepositoryProvider).watchWeekPauseStats(DateTime.now()),
);

final StreamProvider<List<SessionWithStats>> _recentSessionsProvider =
    StreamProvider<List<SessionWithStats>>(
  (Ref ref) => ref.watch(sessionRepositoryProvider).watchRecentSessions(),
);

/// Diario emotivo: barre colorate della settimana, insight testuali e
/// log delle sessioni con badge. Solo dati aggregati.
class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StressColors stressColors =
        Theme.of(context).extension<StressColors>()!;
    final List<DayStress> week =
        ref.watch(_weekStressProvider).value ?? const <DayStress>[];
    final WeekPauseStats? pauses = ref.watch(_weekPausesProvider).value;
    final List<SessionWithStats> sessions =
        ref.watch(_recentSessionsProvider).value ??
            const <SessionWithStats>[];

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.diaryTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          Text(
            context.l10n.diaryWeek,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  StressBarChart(days: week, colors: stressColors),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: <Widget>[
                      _LegendChip(
                        color: stressColors.low,
                        label: context.l10n.stressLow,
                      ),
                      _LegendChip(
                        color: stressColors.medium,
                        label: context.l10n.stressMedium,
                      ),
                      _LegendChip(
                        color: stressColors.high,
                        label: context.l10n.stressHigh,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.diaryLegend,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ..._insights(context, week, pauses),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l10n.diaryRecentSessions,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                context.l10n.diaryEmpty,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final SessionWithStats s in sessions)
              _SessionTile(stats: s, colors: stressColors),
        ],
      ),
    );
  }

  List<Widget> _insights(
    BuildContext context,
    List<DayStress> week,
    WeekPauseStats? pauses,
  ) {
    final List<String> texts = <String>[];
    if (pauses != null && pauses.proposed > 0) {
      texts.add(
        context.l10n.diaryInsightPauses(pauses.accepted, pauses.proposed),
      );
    }
    final int total =
        week.fold(0, (int sum, DayStress d) => sum + d.total);
    final int high =
        week.fold(0, (int sum, DayStress d) => sum + d.highCount);
    if (total > 0) {
      texts.add(
        high / total < 0.15
            ? context.l10n.diaryInsightCalmWeek
            : context.l10n.diaryInsightTenseWeek,
      );
    }
    return <Widget>[
      for (final String text in texts)
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.lightbulb_outline,
              color: AppColors.stressMedium,
            ),
            title: Text(text),
          ),
        ),
    ];
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.stats, required this.colors});

  final SessionWithStats stats;
  final StressColors colors;

  @override
  Widget build(BuildContext context) {
    final DateTime start = stats.session.startedAt;
    final String when =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')} '
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final (Color color, String label) = switch (stats.dominantLevel) {
      StressLevel.basso => (colors.low, context.l10n.stressLow),
      StressLevel.medio => (colors.medium, context.l10n.stressMedium),
      StressLevel.alto => (colors.high, context.l10n.stressHigh),
    };

    return Card(
      child: ListTile(
        leading: Icon(Icons.menu_book_outlined, color: AppColors.primary),
        title: Text(
          '$when · ${context.l10n.diarySessionDuration(stats.duration.inMinutes)}',
        ),
        subtitle: Text(context.l10n.diaryPausesTaken(stats.pausesAccepted)),
        trailing: Chip(
          avatar: CircleAvatar(backgroundColor: color, radius: 6),
          label: Text(label),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
