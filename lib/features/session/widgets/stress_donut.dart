import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Donut colorato dal livello di stress con etichetta testuale al centro:
/// il colore non è mai l'unico canale (WCAG AA / NFR10, niente numeri).
class StressDonut extends StatelessWidget {
  const StressDonut({
    super.key,
    required this.color,
    required this.label,
    this.size = 220,
  });

  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: const Duration(milliseconds: 400),
      builder: (BuildContext context, Color? animated, _) {
        final Color ring = animated ?? color;
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(color: ring),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: ring, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double stroke = AppSpacing.lg;
    final double radius = (size.shortestSide - stroke) / 2;
    final Paint background = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.15);
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, background);
    canvas.drawCircle(center, radius - AppSpacing.xs, ring);
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.color != color;
}
