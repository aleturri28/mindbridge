import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/preferences.dart';

/// Avvisi di stress (FR3/NFR4): discreti per default. Vibrazione sempre
/// (tranne modalità silenziosa), suono SOLO se l'utente lo ha scelto e
/// la modalità biblioteca è spenta.
abstract final class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _silentChannel =
      AndroidNotificationChannel(
    'stress_alerts_silent',
    'Proposte di pausa (discrete)',
    importance: Importance.high,
    playSound: false,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _soundChannel =
      AndroidNotificationChannel(
    'stress_alerts_sound',
    'Proposte di pausa (con suono)',
    importance: Importance.high,
  );

  static Future<void> init() async {
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_silentChannel);
    await android?.createNotificationChannel(_soundChannel);
  }

  /// Da chiamare all'avvio della prima sessione (Android 13+ / iOS).
  static Future<void> ensurePermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
  }

  /// Avviso «potresti beneficiare di una pausa» (NFR9: chiamato entro ~2 s
  /// dal riconoscimento). Le stringhe arrivano dalla UI (l10n).
  static Future<void> showStressAlert({
    required String title,
    required String body,
    required NotificationMode mode,
    required bool libraryMode,
  }) async {
    if (mode != NotificationMode.silent) {
      unawaited(_hapticBurst());
    }
    if (libraryMode) {
      // Modalità biblioteca: solo aptica, nessuna notifica di sistema.
      return;
    }
    final bool withSound = mode == NotificationMode.sound;
    final AndroidNotificationChannel channel =
        withSound ? _soundChannel : _silentChannel;
    await _plugin.show(
      id: 1,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          importance: Importance.high,
          priority: Priority.high,
          playSound: withSound,
          enableVibration: mode != NotificationMode.silent,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: withSound,
        ),
      ),
    );
  }

  /// Tripla vibrazione discreta via feedback aptico.
  static Future<void> _hapticBurst() async {
    for (int i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}
