import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../data/repositories/diary_repository.dart';

/// Barre impilate giorno-per-giorno della settimana (CustomPaint, niente
/// librerie di charting). Il colore è sempre affiancato dalla legenda
/// testuale nella schermata (WCAG AA).
class StressBarChart extends StatelessWidget {
  const StressBarChart({
    super.key,
    required this.days,
    required this.colors,
    this.height = 160,
  });

  final List<DayStress> days;
  final StressColors colors;
  final double height;

  static const List<String> _weekdayLabels = <String>[
    'L', 'M', 'M', 'G', 'V', 'S', 'D',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarsPainter(days: days, colors: colors),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            for (final String label in _weekdayLabels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.days, required this.colors});

  final List<DayStress> days;
  final StressColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) {
      return;
    }
    final double slot = size.width / days.length;
    final double barWidth = slot * 0.5;
    final int maxTotal = days
        .map((DayStress d) => d.total)
        .reduce((int a, int b) => a > b ? a : b);

    for (int i = 0; i < days.length; i++) {
      final DayStress day = days[i];
      final double centerX = slot * i + slot / 2;
      if (day.total == 0 || maxTotal == 0) {
        // Giorno vuoto: trattino neutro come empty state visivo.
        final Paint empty = Paint()
          ..color = Colors.black12
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(centerX - barWidth / 2, size.height - 2),
          Offset(centerX + barWidth / 2, size.height - 2),
          empty,
        );
        continue;
      }
      final double barHeight = size.height * (day.total / maxTotal);
      final double unit = barHeight / day.total;
      double y = size.height;
      // Impilate dal basso: basso → medio → alto.
      for (final (int count, Color color) in <(int, Color)>[
        (day.lowCount, colors.low),
        (day.mediumCount, colors.medium),
        (day.highCount, colors.high),
      ]) {
        if (count == 0) {
          continue;
        }
        final double segment = unit * count;
        final Rect rect = Rect.fromLTWH(
          centerX - barWidth / 2,
          y - segment,
          barWidth,
          segment,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = color,
        );
        y -= segment + 1;
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.days != days || oldDelegate.colors != colors;
}
