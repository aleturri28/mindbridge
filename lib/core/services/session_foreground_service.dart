import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Notifica persistente di sessione su Android (CLAUDE.md Fase 1).
/// Su iOS non esiste l'equivalente: il monitoraggio è comunque solo
/// foreground su entrambe le piattaforme.
abstract final class SessionForegroundService {
  static void init() {
    if (!Platform.isAndroid) {
      return;
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'session_foreground',
        channelName: 'Sessione di studio attiva',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
  }

  static Future<void> start({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: body,
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
