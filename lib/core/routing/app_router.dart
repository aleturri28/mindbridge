import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Nomi delle route. Fase 0: routing vuoto — esiste solo la home placeholder.
/// Le route delle feature (onboarding, session, pause, diary, settings)
/// verranno aggiunte in Fase 1.
abstract final class AppRoutes {
  static const String home = '/';
}

/// Route table centralizzata (Navigator 1.0 con route nominate: nessuna
/// dipendenza di routing finché non serve davvero).
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const _ThemePreviewScreen(),
        );
    }
  }
}

/// Placeholder di Fase 0: schermata vuota che rende verificabile a occhio
/// il tema (token colore, semaforo con etichette, gerarchia bottoni, timer
/// mono). Verrà sostituita dalla Home reale in Fase 1.
class _ThemePreviewScreen extends StatelessWidget {
  const _ThemePreviewScreen();

  @override
  Widget build(BuildContext context) {
    final StressColors stress = Theme.of(context).extension<StressColors>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('MindBridge')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: AppSpacing.md,
            children: <Widget>[
              Text(
                'Fase 0 — Scaffold',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: AppSpacing.sm,
                children: <Widget>[
                  _StressChip(label: 'Basso', color: stress.low),
                  _StressChip(label: 'Medio', color: stress.medium),
                  _StressChip(label: 'Alto', color: stress.high),
                ],
              ),
              Text('25:00', style: AppTheme.timerStyle.copyWith(fontSize: 40)),
              FilledButton(onPressed: () {}, child: const Text('Primario')),
              OutlinedButton(onPressed: () {}, child: const Text('Secondario')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pallino colorato + etichetta testuale: il colore non è mai da solo
/// (WCAG AA, vincolo NFR10).
class _StressChip extends StatelessWidget {
  const _StressChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: AppSpacing.xs + 2),
      label: Text(label),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    );
  }
}
