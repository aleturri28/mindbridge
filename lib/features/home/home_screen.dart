import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';

/// Home: avvio sessione (primario unico), accesso a diario e impostazioni.
/// Long-press sul titolo → menu debug nascosto.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasBaseline = ref.watch(preferencesProvider).baseline != null;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () =>
              Navigator.of(context).pushNamed(AppRoutes.debug),
          child: Text(context.l10n.appTitle),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              Text(
                context.l10n.homeGreeting,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.homeSubtitle,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  hasBaseline ? AppRoutes.session : AppRoutes.calibration,
                ),
                icon: const Icon(Icons.play_arrow),
                label: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(context.l10n.homeStartSession),
                ),
              ),
              if (!hasBaseline) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.homeCalibrationNeeded,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _HomeTile(
                      icon: Icons.bar_chart,
                      label: context.l10n.homeDiary,
                      route: AppRoutes.diary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _HomeTile(
                      icon: Icons.settings_outlined,
                      label: context.l10n.homeSettings,
                      route: AppRoutes.settings,
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
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => Navigator.of(context).pushNamed(route),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: <Widget>[
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
