import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import '../../data/preferences.dart';

/// Impostazioni: tipo di avviso, modalità biblioteca (1 tap, FR3),
/// toggle privacy on-device bloccato con spiegazione, gestione dati.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final Preferences prefs = ref.watch(preferencesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: <Widget>[
          _SectionHeader(context.l10n.settingsNotifications),
          RadioGroup<NotificationMode>(
            groupValue: prefs.notificationMode,
            onChanged: (NotificationMode? mode) async {
              if (mode != null) {
                await prefs.setNotificationMode(mode);
                setState(() {});
              }
            },
            child: Column(
              children: <Widget>[
                RadioListTile<NotificationMode>(
                  value: NotificationMode.vibration,
                  title: Text(context.l10n.settingsNotificationVibration),
                ),
                RadioListTile<NotificationMode>(
                  value: NotificationMode.sound,
                  title: Text(context.l10n.settingsNotificationSound),
                ),
                RadioListTile<NotificationMode>(
                  value: NotificationMode.silent,
                  title: Text(context.l10n.settingsNotificationSilent),
                ),
              ],
            ),
          ),
          SwitchListTile(
            value: prefs.libraryMode,
            onChanged: (bool value) async {
              await prefs.setLibraryMode(value);
              setState(() {});
            },
            title: Text(context.l10n.settingsLibraryMode),
            subtitle: Text(context.l10n.settingsLibraryModeSubtitle),
            secondary: const Icon(Icons.local_library_outlined),
          ),
          const Divider(),
          _SectionHeader(context.l10n.settingsPrivacy),
          // Vincolo NFR1/NFR2: l'elaborazione on-device è una garanzia,
          // il toggle esiste solo per comunicarla ed è bloccato ON.
          SwitchListTile(
            value: true,
            onChanged: null,
            title: Text(context.l10n.settingsOnDevice),
            subtitle: Text(context.l10n.settingsOnDeviceSubtitle),
            secondary: const Icon(Icons.verified_user_outlined),
          ),
          const Divider(),
          _SectionHeader(context.l10n.settingsData),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(context.l10n.settingsRecalibrate),
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.calibration),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline,
                color: AppColors.stressHigh),
            title: Text(
              context.l10n.settingsDeleteData,
              style: const TextStyle(color: AppColors.stressHigh),
            ),
            onTap: _confirmDeleteAll,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.settingsDeleteDataConfirmTitle),
        content: Text(context.l10n.settingsDeleteDataConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.stressHigh,
            ),
            child: Text(context.l10n.settingsDeleteDataConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(databaseProvider).deleteAllData();
    await ref.read(preferencesProvider).clearPersonalData();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsDataDeleted)),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
            ),
      ),
    );
  }
}
