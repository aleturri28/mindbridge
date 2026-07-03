import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../classifier/baseline.dart';

/// Modalità di avviso preferita (NFR4: default vibrazione, mai suono
/// non richiesto).
enum NotificationMode { vibration, sound, silent }

/// Preferenze utente e baseline di calibrazione (shared_preferences).
class Preferences {
  Preferences(this._prefs);

  static const String _kOnboardingDone = 'onboardingDone';
  static const String _kNotificationMode = 'notificationMode';
  static const String _kLibraryMode = 'libraryMode';
  static const String _kBaseline = 'baseline';
  static const String _kUseSimulatedSensing = 'useSimulatedSensing';

  final SharedPreferences _prefs;

  static Future<Preferences> load() async =>
      Preferences(await SharedPreferences.getInstance());

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone(bool value) =>
      _prefs.setBool(_kOnboardingDone, value);

  NotificationMode get notificationMode {
    final int? index = _prefs.getInt(_kNotificationMode);
    return index == null
        ? NotificationMode.vibration
        : NotificationMode.values[index];
  }

  Future<void> setNotificationMode(NotificationMode mode) =>
      _prefs.setInt(_kNotificationMode, mode.index);

  /// Modalità biblioteca: solo aptica, qualunque sia la modalità scelta.
  bool get libraryMode => _prefs.getBool(_kLibraryMode) ?? false;
  Future<void> setLibraryMode(bool value) =>
      _prefs.setBool(_kLibraryMode, value);

  Baseline? get baseline {
    final String? raw = _prefs.getString(_kBaseline);
    if (raw == null) {
      return null;
    }
    return Baseline.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setBaseline(Baseline? value) async {
    if (value == null) {
      await _prefs.remove(_kBaseline);
    } else {
      await _prefs.setString(_kBaseline, jsonEncode(value.toJson()));
    }
  }

  /// Fase 1: sempre true. Diventerà commutabile dal menu debug quando
  /// esisterà CameraSensingSource (Fase 2+).
  bool get useSimulatedSensing =>
      _prefs.getBool(_kUseSimulatedSensing) ?? true;
  Future<void> setUseSimulatedSensing(bool value) =>
      _prefs.setBool(_kUseSimulatedSensing, value);

  /// Impostazioni → «Cancella tutti i dati»: azzera anche le preferenze
  /// legate ai dati personali (baseline), mantiene quelle di UX.
  Future<void> clearPersonalData() async {
    await _prefs.remove(_kBaseline);
  }
}
