import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Tema Material 3 costruito sui design token del medium-fi.
///
/// Gerarchia bottoni (dal report):
/// - un solo primario pieno per schermata → [FilledButton];
/// - secondari outline blu → [OutlinedButton];
/// - il grigio è riservato agli elementi non interattivi.
abstract final class AppTheme {
  static ThemeData light() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
          primary: AppColors.primary,
          error: AppColors.stressHigh,
          surface: AppColors.background,
        );

    final RoundedRectangleBorder pillShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.pill),
    );

    return ThemeData(
      colorScheme: scheme,
      fontFamily: AppFonts.ui,
      scaffoldBackgroundColor: AppColors.background,
      extensions: const <ThemeExtension<dynamic>>[StressColors.standard],

      // Card radius 12 dp.
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),

      // Pill button 24 dp.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: pillShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pillShape,
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: pillShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pillShape),
      ),

      // Bottom sheet notifica stress: angoli superiori arrotondati.
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.card),
          ),
        ),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.black87,
        centerTitle: true,
      ),
    );
  }

  /// Stile per i timer (Roboto Mono, cifre tabulari implicite nel mono).
  static const TextStyle timerStyle = TextStyle(
    fontFamily: AppFonts.mono,
    fontWeight: FontWeight.w500,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
