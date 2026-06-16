import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    _initialized = true;
  }

  static Future<void> showWhistleAlert(int count, int target) async {
    const channel = AndroidNotificationDetails(
      'whistle_alert',
      'Whistle Alert',
      channelDescription: 'Pressure cooker whistle target alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );
    const details = NotificationDetails(android: channel);
    await _plugin.show(
      1001,
      'Cooker Alert',
      '$count whistle${count == 1 ? "" : "s"} completed - time to check the cooker!',
      details,
    );
  }
}
