import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_tokens.dart';
import '../../sensing/sensing_sample.dart';
import '../../sensing/simulated_sensing_source.dart';
import '../session/session_controller.dart';

/// Menu debug nascosto (long-press sul titolo in Home). Strumento di
/// sviluppo/demo: qui — e SOLO qui — si vedono valori numerici grezzi
/// (l'eccezione consentita a NFR10). Testi non localizzati di proposito.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  @override
  Widget build(BuildContext context) {
    final SimulatedSensingSource simulator =
        ref.watch(simulatedSensingProvider);
    final SessionState session = ref.watch(sessionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Debug — simulatore')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          Text(
            'Stress simulato: ${simulator.targetStress.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: simulator.targetStress,
            onChanged: (double value) =>
                setState(() => simulator.targetStress = value),
          ),
          Row(
            children: <Widget>[
              for (final (String label, double value) in <(String, double)>[
                ('Basso', 0), ('Medio', 0.55), ('Alto', 1),
              ]) ...<Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => simulator.targetStress = value),
                    child: Text(label),
                  ),
                ),
                if (value < 1) const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Qualità rPPG simulata: '
            '${simulator.simulatedHrQuality.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: simulator.simulatedHrQuality,
            onChanged: (double value) =>
                setState(() => simulator.simulatedHrQuality = value),
          ),
          const Divider(),
          SwitchListTile(
            value: true,
            onChanged: null,
            title: const Text('Sorgente simulata'),
            subtitle: const Text(
              'Lo switch sim/reale per la sessione arriva in Fase 4',
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.android)
            ListTile(
              title: const Text('Sensing camera (Fase 2)'),
              subtitle: const Text(
                'Preview + landmark MediaPipe + metriche grezze',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.debugSensing),
            ),
          const Divider(),
          ListTile(
            title: const Text('Stato sessione'),
            subtitle: Text(
              'phase: ${session.phase.name} · level: ${session.level.name} · '
              'alert: ${session.stressAlert} · '
              'elapsed: ${session.elapsed.inSeconds}s',
            ),
          ),
          StreamBuilder<SensingSample>(
            stream: simulator.signals,
            builder: (
              BuildContext context,
              AsyncSnapshot<SensingSample> snapshot,
            ) {
              final SensingSample? s = snapshot.data;
              return ListTile(
                title: const Text('Ultimo campione (valori grezzi)'),
                subtitle: Text(
                  s == null
                      ? 'nessun campione: la sorgente emette solo durante '
                          'calibrazione o sessione'
                      : 'hr: ${s.hr?.toStringAsFixed(1) ?? '—'} bpm · '
                          'quality: ${s.hrQuality.toStringAsFixed(2)}\n'
                          'tensione: ${s.facialTension.toStringAsFixed(2)} · '
                          'postura: ${s.postureScore.toStringAsFixed(2)}',
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
