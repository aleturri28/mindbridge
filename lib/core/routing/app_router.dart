import 'package:flutter/material.dart';

import '../../data/pause_types.dart';
import '../../features/debug/debug_screen.dart';
import '../../features/debug/sensing_debug_screen.dart';
import '../../features/diary/diary_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/pause/breathing_screen.dart';
import '../../features/pause/music_screen.dart';
import '../../features/pause/pause_choice_screen.dart';
import '../../features/pause/pause_done_screen.dart';
import '../../features/pause/stretching_screen.dart';
import '../../features/session/calibration_screen.dart';
import '../../features/session/session_screen.dart';
import '../../features/settings/settings_screen.dart';

/// Nomi delle route dell'app (riferimento: 17 schermate del medium-fi).
abstract final class AppRoutes {
  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String calibration = '/calibration';
  static const String session = '/session';
  static const String pauseChoice = '/pause-choice';
  static const String pauseBreathing = '/pause/breathing';
  static const String pauseStretching = '/pause/stretching';
  static const String pauseMusic = '/pause/music';
  static const String pauseDone = '/pause/done';
  static const String diary = '/diary';
  static const String settings = '/settings';
  static const String debug = '/debug';
  static const String debugSensing = '/debug/sensing';
}

/// Route table centralizzata (Navigator 1.0 con route nominate: nessuna
/// dipendenza di routing finché non serve davvero).
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final WidgetBuilder builder = switch (settings.name) {
      AppRoutes.home => (_) => const HomeScreen(),
      AppRoutes.onboarding => (_) => const OnboardingScreen(),
      AppRoutes.calibration => (_) => const CalibrationScreen(),
      AppRoutes.session => (_) => const SessionScreen(),
      AppRoutes.pauseChoice => (_) => const PauseChoiceScreen(),
      AppRoutes.pauseBreathing => (_) => const BreathingScreen(),
      AppRoutes.pauseStretching => (_) => const StretchingScreen(),
      AppRoutes.pauseMusic => (_) => const MusicScreen(),
      AppRoutes.pauseDone => (_) => PauseDoneScreen(
            kind: settings.arguments is PauseKind
                ? settings.arguments! as PauseKind
                : PauseKind.breathing,
          ),
      AppRoutes.diary => (_) => const DiaryScreen(),
      AppRoutes.settings => (_) => const SettingsScreen(),
      AppRoutes.debug => (_) => const DebugScreen(),
      AppRoutes.debugSensing => (_) => const SensingDebugScreen(),
      _ => (_) => const HomeScreen(),
    };
    return MaterialPageRoute<void>(settings: settings, builder: builder);
  }
}
