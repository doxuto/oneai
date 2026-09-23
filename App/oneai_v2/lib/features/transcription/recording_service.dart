import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// S11-09 — Android keeps the mic only while a foreground service with a
/// notification is running (mandatory on Android 14+, type `microphone`).
/// iOS needs nothing here: the `audio` background mode keeps the session.
/// The service does no work of its own — the recorder runs in the main
/// isolate; the notification is what stops the OS from killing us.
class RecordingService {
  static bool _inited = false;

  static void _init() {
    if (_inited) return;
    _inited = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'recording',
        channelName: 'Recording',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        showBadge: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing(), autoRunOnBoot: false, allowWakeLock: true),
    );
  }

  /// Starts (or updates) the persistent "Recording…" notification. No-op off Android.
  static Future<void> start({required String title, required String text}) async {
    if (!Platform.isAndroid) return;
    _init();
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
      } else {
        await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.microphone],
          notificationTitle: title,
          notificationText: text,
          callback: recordingServiceEntry,
        );
      }
    } on Object catch (_) {
      // A missing manifest entry (PLATFORM-SETUP.md) must not stop the recording itself.
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } on Object catch (_) {}
  }
}

/// Top-level entry the plugin runs in its own isolate; nothing to do there.
@pragma('vm:entry-point')
void recordingServiceEntry() {
  FlutterForegroundTask.setTaskHandler(_NoopHandler());
}

class _NoopHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
