import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final granted = await androidPlugin?.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<void> showPoolLowBalanceNotification({
    required String groupName,
    required double balance,
    required double percentage,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'pool_low_balance',
      'Pool Balance Alerts',
      channelDescription: 'Alerts when pool balance is running low',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      1,
      '⚠️ Low Pool Balance - $groupName',
      'Pool balance is ₹${balance.toStringAsFixed(0)} (${percentage.toStringAsFixed(0)}% remaining). Consider topping up!',
      details,
    );
  }

  Future<void> showSettleUpReminder({required String groupName}) async {
    const androidDetails = AndroidNotificationDetails(
      'settle_up_reminder',
      'Settle Up Reminders',
      channelDescription: 'Monthly reminders to settle up balances',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      2,
      '💰 Time to Settle Up!',
      'Don\'t forget to settle your balances in $groupName.',
      details,
    );
  }

  Future<void> scheduleMonthlyReminder() async {
    // Schedule a monthly reminder (using periodic notification as simplified version)
    const androidDetails = AndroidNotificationDetails(
      'monthly_reminder',
      'Monthly Reminders',
      channelDescription: 'Monthly expense summary reminders',
      importance: Importance.low,
      priority: Priority.low,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.periodicallyShow(
      3,
      '📊 Monthly Summary',
      'Review your group expenses and settle up balances.',
      RepeatInterval.weekly,
      details,
      androidScheduleMode: AndroidScheduleMode.inexact,
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}

