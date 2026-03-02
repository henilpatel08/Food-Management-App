import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();
  static FlutterLocalNotificationsPlugin get plugin => _plugin;


  // 🔹 Call this once in main() before using notifications
  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(initializationSettings);
  }

  // 🔹 Show expiry-style notification with custom funny message
  static Future<void> showExpiryNotification({
    required String ingredient,
    required String message,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'expiry_channel',
      'Ingredient Alerts',
      channelDescription: 'Fun reminders for ingredients',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      ingredient.hashCode,
      message,  // 👈 message becomes the TITLE
      null,     // 👈 no body text
      notificationDetails,
    );
  }

}
