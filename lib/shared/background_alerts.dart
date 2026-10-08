import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'logger.dart';

/// Keeps the app alive in the background (Android foreground service) and
/// shows a system notification — heads-up banner plus the default sound —
/// when something arrives while the app is not on screen.
///
/// No Firebase / push server: the app's own connection (Realtime + 5 s poll,
/// see realtime_sync.dart) keeps running because the foreground service stops
/// Android from freezing the process. Limits:
///   * swiping the app away from the recent-apps list ends it, like any app;
///   * some phone makers (Xiaomi, Huawei, Samsung…) kill background apps
///     unless the app is exempt from battery optimisation (requested on start);
///   * Android only. On other platforms every method is a no-op.
class BackgroundAlerts {
  BackgroundAlerts._();
  static final BackgroundAlerts instance = BackgroundAlerts._();

  static const _channelId = 'eshary_alerts';
  static const _icon = '@mipmap/ic_launcher';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True when the app is not the screen the user is looking at.
  bool get inBackground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s != null && s != AppLifecycleState.resumed;
  }

  /// Call once from main(), before runApp.
  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      FlutterForegroundTask.initCommunicationPort();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_icon),
        ),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // High importance = heads-up banner on top of the screen + sound.
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'إشعارات العمليات والرسائل',
          description: 'عمليات الموظفين ورسائل المدير',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'eshary_background',
          channelName: 'التشغيل في الخلفية',
          channelDescription:
              'يبقي التطبيق متصلاً لاستقبال الإشعارات والتنبيه بصوت.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _ready = true;
    } catch (e, st) {
      AppLogger.error('[bg] init failed', e, st);
    }
  }

  /// Ask for the permissions the feature needs, then start the service.
  /// Safe to call repeatedly (e.g. every time a home shell opens).
  Future<void> start() async {
    if (!supported || !_ready) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Android 13+: notifications need a runtime permission.
      await android?.requestNotificationsPermission();

      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 4711,
        serviceTypes: [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: 'إشاري يعمل في الخلفية',
        notificationText: 'لاستقبال إشعارات العمليات والرسائل',
        callback: _startCallback,
      );
    } catch (e, st) {
      AppLogger.error('[bg] start failed', e, st);
    }
  }

  /// Stop the service (sign-out), so no notification stays behind.
  Future<void> stop() async {
    if (!supported || !_ready) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e, st) {
      AppLogger.error('[bg] stop failed', e, st);
    }
  }

  /// Heads-up system notification with the default sound.
  Future<void> notify({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!supported || !_ready) return;
    try {
      await _plugin.show(
        id: id & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'إشعارات العمليات والرسائل',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.message,
            // On a locked screen show only "content hidden": amounts and
            // names must not be readable by someone holding the phone.
            visibility: NotificationVisibility.private,
            styleInformation: BigTextStyleInformation(''),
          ),
        ),
      );
    } catch (e, st) {
      AppLogger.error('[bg] notify failed', e, st);
    }
  }
}

/// The service needs a handler; all the work stays in the app's own isolate
/// (single session, no second connection), so this one does nothing.
@pragma('vm:entry-point')
void _startCallback() {
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
