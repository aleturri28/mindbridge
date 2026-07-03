import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/routing/app_router.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_foreground_service.dart';
import 'data/preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Preferences prefs = await Preferences.load();
  await NotificationService.init();
  SessionForegroundService.init();
  // Riverpod scelto in Fase 0 come state management unico (CLAUDE.md).
  runApp(
    ProviderScope(
      overrides: [preferencesProvider.overrideWithValue(prefs)],
      child: MindBridgeApp(
        initialRoute:
            prefs.onboardingDone ? AppRoutes.home : AppRoutes.onboarding,
      ),
    ),
  );
}
