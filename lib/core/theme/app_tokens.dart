import 'package:flutter/material.dart';

/// Design token dal prototipo medium-fi (CLAUDE.md: rispettarli alla lettera).
///
/// Qualsiasi colore, spaziatura o raggio usato nella UI deve passare da qui:
/// niente valori hardcoded sparsi nelle schermate.
abstract final class AppColors {
  /// Primario (azioni, brand).
  static const Color primary = Color(0xFF4A90D9);

  /// Successo / stress Basso (semaforo verde).
  static const Color stressLow = Color(0xFF2ECC71);

  /// Accent / stress Medio (semaforo arancio).
  static const Color stressMedium = Color(0xFFF39C12);

  /// Alert / stress Alto (semaforo rosso). Usato anche per «Stop» sessione.
  static const Color stressHigh = Color(0xFFE74C3C);

  /// Sfondo app.
  static const Color background = Color(0xFFF8F9FA);
}

/// Griglia 8 dp: usare sempre multipli di [unit].
abstract final class AppSpacing {
  static const double unit = 8;
  static const double xs = unit / 2; // 4
  static const double sm = unit; // 8
  static const double md = unit * 2; // 16
  static const double lg = unit * 3; // 24
  static const double xl = unit * 4; // 32
}

/// Raggi dei contenitori.
abstract final class AppRadii {
  /// Card radius 12 dp.
  static const double card = 12;

  /// Pill button 24 dp.
  static const double pill = 24;
}

/// Famiglie tipografiche (bundled in assets/fonts, nessun fetch runtime).
abstract final class AppFonts {
  /// Font UI.
  static const String ui = 'Roboto';

  /// Font monospace per i timer.
  static const String mono = 'Roboto Mono';
}

/// Colori del semaforo di stress come [ThemeExtension], così le schermate
/// li leggono dal tema (`Theme.of(context).extension<StressColors>()`).
///
/// NFR10/WCAG AA: il colore non è mai l'unico canale — va sempre accompagnato
/// dall'etichetta testuale Basso/Medio/Alto.
@immutable
class StressColors extends ThemeExtension<StressColors> {
  const StressColors({
    required this.low,
    required this.medium,
    required this.high,
  });

  final Color low;
  final Color medium;
  final Color high;

  static const StressColors standard = StressColors(
    low: AppColors.stressLow,
    medium: AppColors.stressMedium,
    high: AppColors.stressHigh,
  );

  @override
  StressColors copyWith({Color? low, Color? medium, Color? high}) {
    return StressColors(
      low: low ?? this.low,
      medium: medium ?? this.medium,
      high: high ?? this.high,
    );
  }

  @override
  StressColors lerp(ThemeExtension<StressColors>? other, double t) {
    if (other is! StressColors) {
      return this;
    }
    return StressColors(
      low: Color.lerp(low, other.low, t)!,
      medium: Color.lerp(medium, other.medium, t)!,
      high: Color.lerp(high, other.high, t)!,
    );
  }
}
