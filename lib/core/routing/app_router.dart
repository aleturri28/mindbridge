import 'package:flutter/material.dart';

import '../../features/home/home_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
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
}

/// Route table centralizzata (Navigator 1.0 con route nominate: nessuna
/// dipendenza di routing finché non serve davvero).
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final WidgetBuilder builder = switch (settings.name) {
      AppRoutes.home => (_) => const HomeScreen(),
      AppRoutes.onboarding => (_) => const OnboardingScreen(),
      AppRoutes.settings => (_) => const SettingsScreen(),
      _ => (_) => const _UnderConstructionScreen(),
    };
    return MaterialPageRoute<void>(settings: settings, builder: builder);
  }
}

/// Segnaposto temporaneo per le route non ancora implementate in Fase 1.
/// Sparisce man mano che le schermate vengono aggiunte.
class _UnderConstructionScreen extends StatelessWidget {
  const _UnderConstructionScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(child: Icon(Icons.construction)),
    );
  }
}
