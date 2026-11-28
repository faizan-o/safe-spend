import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/dashboard_controller.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../utils/formatters.dart';
import 'notification_service.dart';
import 'reminder_planner.dart';

/// Keeps the phone's reminders in step with the user's data.
///
/// It listens to the shared [DashboardController]. A moment after anything
/// changes (a bill is paid, a date is edited, a setting is switched) it works
/// out the reminders again and replaces the scheduled ones. It also shows an
/// alert when a category reaches 90% of its limit or goes over.
class NotificationCoordinator {
  NotificationCoordinator(this.controller, {NotificationService? service})
      : service = service ?? NotificationService.instance;

  final DashboardController controller;
  final NotificationService service;

  static const String _askedKey = 'notifications.asked';
  static const String _seenKey = 'notifications.seenBudgets';
  static const String _alertsKey = 'notifications.alerts';

  Timer? _timer;
  Timer? _heartbeat;
  bool _running = false;
  bool _again = false;
  bool _started = false;
  bool _disposed = false;
  String? _lastSignature;

  void start() {
    if (_started || !service.supported) return;
    _started = true;
    unawaited(service.init());
    controller.addListener(_onChange);
    // A day passing (or the machine waking up) changes what is due, even when no data changed.
    _heartbeat = Timer.periodic(const Duration(hours: 6), (_) => refresh(force: true));
    _onChange();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _heartbeat?.cancel();
    if (_started) controller.removeListener(_onChange);
  }

  /// Run again soon, for example after the app comes back to the front or the
  /// user changed a reminder setting.
  void refresh({bool force = false}) {
    if (force) _lastSignature = null;
    _onChange();
  }

  void _onChange() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      await _sync();
    } catch (error) {
      debugPrint('Reminder sync failed: $error');
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        _onChange();
      }
    }
  }

  Future<void> _sync() async {
    final profile = controller.profile;
    if (profile == null || controller.loading) return;
    final settings = profile.reminder;

    var allowed = await service.hasPermission();
    if (!allowed && settings.anyScheduled) allowed = await _askOnce();
    if (!allowed) {
      if (_lastSignature != 'off') await service.cancelScheduled();
      _lastSignature = 'off';
      return;
    }

    final now = DateTime.now();
    final today = DateKeys.ofDay(now);
    final plan = settings.anyScheduled
        ? ReminderPlanner.plan(
            now: now,
            settings: settings,
            symbol: controller.symbol,
            recurring: controller.recurring,
            debts: controller.debts,
            loggedToday: controller.recentExpenses.any((e) => e.dayKey == today),
            spentToday: controller.todayExpenses.fold<int>(0, (sum, e) => sum + e.amount),
          )
        : const <PlannedReminder>[];

    // Only touch the phone when something changed.
    final signature = '$today|${plan.map((p) => p.signature).join(';')}';
    if (signature != _lastSignature) {
      await service.replaceScheduled(plan);
      _lastSignature = signature;
    }

    if (settings.budgetAlerts) await _budgetAlerts();
  }

  /// Asks for permission the first time only; after that the Settings screen
  /// has a button for it.
  Future<bool> _askOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) ?? false) return false;
    await prefs.setBool(_askedKey, true);
    return service.requestPermission();
  }

  // ---- Budget alerts --------------------------------------------------------

  Future<void> _budgetAlerts() async {
    final budget = controller.budget;
    if (budget == null) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
    final sent = (prefs.getStringList(_alertsKey) ?? const <String>[]).toSet();
    final firstLook = !seen.contains(budget.id);

    final symbol = controller.symbol;
    for (final row in controller.rows) {
      if (row.line.kind != CategoryKind.flexible || row.line.limit <= 0) continue;
      final ratio = row.usedRatio;
      final over = ratio >= 1.0;
      final near = ratio >= 0.9;
      if (!near) continue;

      final overKey = '${budget.id}|${row.line.categoryId}|over';
      final nearKey = '${budget.id}|${row.line.categoryId}|near';
      final newOver = over && !sent.contains(overKey);
      final newNear = near && !sent.contains(nearKey);
      if (over) sent.add(overKey);
      sent.add(nearKey);
      if (firstLook) continue; // existing state is recorded, not announced
      if (newOver) {
        final by = row.spent - row.line.limit;
        await service.show(
          id: _alertId(overKey),
          title: '${row.line.name} is over budget',
          body: by > 0
              ? 'You are ${formatMoney(by, symbol)} over the ${formatMoney(row.line.limit, symbol)} limit.'
              : 'You have used all of the ${formatMoney(row.line.limit, symbol)} limit.',
          channel: ReminderChannel.budget,
          payload: ReminderPayload.budget,
        );
      } else if (newNear) {
        final left = row.line.limit - row.spent;
        await service.show(
          id: _alertId(nearKey),
          title: '${row.line.name} is almost used up',
          body: '${formatMoney(left, symbol)} left of ${formatMoney(row.line.limit, symbol)}.',
          channel: ReminderChannel.budget,
          payload: ReminderPayload.budget,
        );
      }
    }

    seen.add(budget.id);
    await prefs.setStringList(_seenKey, seen.toList());
    await prefs.setStringList(_alertsKey, sent.toList());
  }

  /// A stable id for an alert, away from the ids used by scheduled reminders.
  static int _alertId(String key) => 100000 + (key.hashCode & 0xFFFFF);
}
