import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

/// A notification that is waiting to be shown (for the Settings screen).
class PendingReminder {
  const PendingReminder({required this.id, required this.title, required this.body});

  final int id;
  final String title;
  final String body;
}

/// The phone's notification system: asking permission, scheduling reminders
/// and showing alerts. Works on Android, iOS and macOS. On the web, Windows
/// and Linux [supported] is false and every call quietly does nothing.
///
/// Reminders are scheduled on the device itself, so they arrive even when the
/// app is closed and need no server.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Scheduled reminders use ids below this; alerts and tests use higher ones.
  static const int _scheduledLimit = 1000;
  static const int _testNowId = 9000;
  static const int _testLaterId = 9001;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();
  bool _ready = false;

  /// Payloads of notifications the user tapped while the app was running.
  Stream<String> get taps => _taps.stream;

  /// The payload of the notification that opened the app from closed, if any.
  String? launchPayload;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) _taps.add(payload);
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        launchPayload = launch.notificationResponse?.payload;
      }
      final android = _android;
      if (android != null) {
        for (final channel in ReminderChannel.values) {
          await android.createNotificationChannel(AndroidNotificationChannel(
            _channelId(channel),
            _channelName(channel),
            description: _channelDescription(channel),
            importance: Importance.high,
          ));
        }
      }
      _ready = true;
    } catch (error) {
      debugPrint('Notifications could not start: $error');
    }
  }

  // ---- Permission -----------------------------------------------------------

  /// True when the user has allowed notifications.
  Future<bool> hasPermission() async {
    if (!supported) return false;
    await init();
    try {
      if (_isAndroid) return await _android?.areNotificationsEnabled() ?? false;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return (await ios?.checkPermissions())?.isEnabled ?? false;
      }
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      return (await mac?.checkPermissions())?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system permission prompt. Returns true when allowed.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    try {
      if (_isAndroid) return await _android?.requestNotificationsPermission() ?? false;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      return await mac?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android 12+ only lets an app fire at the exact minute if the user allows
  /// it; without that, reminders can arrive a few minutes late.
  Future<bool> canScheduleExact() async {
    if (!_isAndroid) return true;
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system screen where exact alarms can be allowed.
  Future<void> requestExactAlarms() async {
    if (!_isAndroid) return;
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  // ---- Showing and scheduling -----------------------------------------------

  /// Shows a notification right now.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required ReminderChannel channel,
    String payload = '',
  }) async {
    if (!supported) return;
    await init();
    try {
      await _plugin.show(id, title, body, _details(channel), payload: payload);
    } catch (error) {
      debugPrint('Could not show notification: $error');
    }
  }

  Future<void> showTest() => show(
        id: _testNowId,
        title: 'SafeSpend notifications work',
        body: 'You will get reminders about spending, bills and budgets here.',
        channel: ReminderChannel.daily,
        payload: ReminderPayload.daily,
      );

  /// Schedules a notification [seconds] from now, to check that scheduled
  /// reminders arrive while the app is closed.
  Future<bool> scheduleTest({int seconds = 15}) async {
    if (!supported) return false;
    await init();
    try {
      await _schedule(
        PlannedReminder(
          id: _testLaterId,
          when: DateTime.now().add(Duration(seconds: seconds)),
          title: 'Scheduled reminder works',
          body: 'This was set up $seconds seconds ago, with the app closed or open.',
          channel: ReminderChannel.daily,
          payload: ReminderPayload.daily,
        ),
        exact: await canScheduleExact(),
      );
      return true;
    } catch (error) {
      debugPrint('Could not schedule the test: $error');
      return false;
    }
  }

  /// Replaces every scheduled reminder with [reminders]. Alerts already shown
  /// stay in the tray.
  Future<void> replaceScheduled(List<PlannedReminder> reminders) async {
    if (!supported) return;
    await init();
    try {
      await _cancelScheduled();
      final exact = await canScheduleExact();
      for (final reminder in reminders) {
        try {
          await _schedule(reminder, exact: exact);
        } catch (error) {
          debugPrint('Could not schedule "${reminder.title}": $error');
        }
      }
    } catch (error) {
      debugPrint('Could not update reminders: $error');
    }
  }

  Future<void> cancelScheduled() async {
    if (!supported) return;
    await init();
    try {
      await _cancelScheduled();
    } catch (_) {}
  }

  /// The reminders waiting to go off, soonest first is not guaranteed by the
  /// system, so callers sort by id (the plan numbers them in time order).
  Future<List<PendingReminder>> pending() async {
    if (!supported) return const [];
    await init();
    try {
      final all = await _plugin.pendingNotificationRequests();
      final list = [
        for (final p in all)
          if (p.id < _scheduledLimit) PendingReminder(id: p.id, title: p.title ?? '', body: p.body ?? ''),
      ]..sort((a, b) => a.id.compareTo(b.id));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _cancelScheduled() async {
    final all = await _plugin.pendingNotificationRequests();
    for (final p in all) {
      if (p.id < _scheduledLimit) await _plugin.cancel(p.id);
    }
  }

  Future<void> _schedule(PlannedReminder r, {required bool exact}) {
    // An exact moment in time; no time zone database is needed for that.
    final when = tz.TZDateTime.from(r.when, tz.UTC);
    return _plugin.zonedSchedule(
      r.id,
      r.title,
      r.body,
      when,
      _details(r.channel),
      payload: r.payload,
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  NotificationDetails _details(ReminderChannel channel) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId(channel),
        _channelName(channel),
        channelDescription: _channelDescription(channel),
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );
  }

  static String _channelId(ReminderChannel channel) => switch (channel) {
        ReminderChannel.daily => 'daily_reminder',
        ReminderChannel.bills => 'bills_due',
        ReminderChannel.budget => 'budget_alerts',
      };

  static String _channelName(ReminderChannel channel) => switch (channel) {
        ReminderChannel.daily => 'Daily reminder',
        ReminderChannel.bills => 'Bills and debts',
        ReminderChannel.budget => 'Budget alerts',
      };

  static String _channelDescription(ReminderChannel channel) => switch (channel) {
        ReminderChannel.daily => 'A daily nudge to log your spending',
        ReminderChannel.bills => 'Bills, income, debts and loans that are coming due',
        ReminderChannel.budget => 'When a category is close to or over its limit',
      };
}
