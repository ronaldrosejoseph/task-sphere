import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

class NotificationService {
  static final NotificationService instance = NotificationService();

  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _notifications = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    // Without this, tz.local falls back to UTC and reminders fire at the
    // wrong wall-clock time.
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Local timezone detection error: $e');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _notifications.initialize(settings: initSettings);
      _initialized = true;
    } catch (e) {
      // Plugin unavailable (e.g. tests, unsupported platform).
      debugPrint('Notification init error: $e');
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'task_sphere_channel',
      'Task Reminders',
      channelDescription: 'Notifications for task due dates and assignments',
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('Notification display error: $e');
    }
  }

  Future<void> scheduleTaskReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized) await init();
    if (scheduledDate.isBefore(DateTime.now())) return;

    final tzDateTime = tz.TZDateTime.from(scheduledDate, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'task_sphere_channel',
      'Task Reminders',
      channelDescription: 'Notifications for task due dates and assignments',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    try {
      await _notifications.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzDateTime,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Notification scheduling error: $e');
    }
  }
}
