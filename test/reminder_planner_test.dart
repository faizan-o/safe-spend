import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/models/debt.dart';
import 'package:safespend/models/recurring.dart';
import 'package:safespend/models/user_profile.dart';
import 'package:safespend/notifications/reminder_planner.dart';

RecurringItem _bill(String due, {int remind = 3, bool active = true, Frequency frequency = Frequency.monthly}) {
  return RecurringItem(
    title: 'Rent',
    amount: 4000000,
    startDay: due,
    nextDueDay: due,
    frequency: frequency,
    remindDays: remind,
    active: active,
  );
}

List<PlannedReminder> _plan({
  required DateTime now,
  ReminderSettings settings = const ReminderSettings(),
  List<RecurringItem> recurring = const [],
  List<Debt> debts = const [],
  bool loggedToday = false,
}) {
  return ReminderPlanner.plan(
    now: now,
    settings: settings,
    symbol: 'Rs.',
    recurring: recurring,
    debts: debts,
    loggedToday: loggedToday,
  );
}

void main() {
  final morning = DateTime(2026, 11, 28, 8, 0);

  group('daily reminder', () {
    test('is scheduled at the chosen time for the next days', () {
      final plan = _plan(now: morning, settings: const ReminderSettings(hour: 20, minute: 30, bills: false, debts: false));
      expect(plan.length, ReminderPlanner.dailyDays);
      expect(plan.first.when, DateTime(2026, 11, 28, 20, 30));
      expect(plan.every((p) => p.channel == ReminderChannel.daily), isTrue);
    });

    test('skips today once the time has passed or spending is already logged', () {
      const s = ReminderSettings(hour: 21, bills: false, debts: false);
      expect(_plan(now: DateTime(2026, 11, 28, 22, 0), settings: s).first.when.day, 29);
      expect(_plan(now: morning, settings: s, loggedToday: true).first.when.day, 29);
    });

    test('can be switched off', () {
      expect(_plan(now: morning, settings: const ReminderSettings(enabled: false)), isEmpty);
    });
  });

  group('bills', () {
    const off = ReminderSettings(enabled: false);

    test('remind ahead and on the day', () {
      final plan = _plan(now: morning, settings: off, recurring: [_bill('2026-12-05', frequency: Frequency.once)]);
      expect(plan.length, 2);
      expect(plan[0].when, DateTime(2026, 12, 2, 9));
      expect(plan[0].title, 'Rent is due in 3 days');
      expect(plan[1].when, DateTime(2026, 12, 5, 9));
      expect(plan[1].title, 'Rent is due today');
      expect(plan[0].payload, ReminderPayload.bills);
    });

    test('a monthly bill is planned for its next dates too', () {
      final plan = _plan(now: morning, settings: off, recurring: [_bill('2026-12-01')]);
      expect(plan.any((p) => p.when.month == 1), isTrue);
    });

    test('paused bills and switched-off kinds are left out', () {
      expect(_plan(now: morning, settings: off, recurring: [_bill('2026-12-05', active: false)]), isEmpty);
      expect(_plan(now: morning, settings: off.copyWith(bills: false), recurring: [_bill('2026-12-05')]), isEmpty);
    });

    test('an overdue bill is nudged for three days', () {
      final plan = _plan(now: morning, settings: off, recurring: [_bill('2026-11-25', frequency: Frequency.once)]);
      expect(plan.length, 3);
      expect(plan.first.title, contains('overdue'));
    });

    test('a bill due today after the reminder hour is not scheduled in the past', () {
      final plan = _plan(now: DateTime(2026, 11, 28, 12), settings: off, recurring: [_bill('2026-11-28', frequency: Frequency.once)]);
      expect(plan, isEmpty);
    });
  });

  group('debts', () {
    final owed = Debt(
      direction: DebtDirection.owedByMe,
      person: 'Ali',
      amount: 500000,
      date: DateTime(2026, 11, 1),
      dueDay: '2026-12-01',
    );

    test('a debt to repay is announced before and on the due date', () {
      final plan = _plan(now: morning, settings: const ReminderSettings(enabled: false), debts: [owed]);
      expect(plan.map((p) => p.when), [DateTime(2026, 11, 28, 9), DateTime(2026, 12, 1, 9)]);
      expect(plan.first.title, 'Repay Ali in 3 days');
      expect(plan.every((p) => p.payload == ReminderPayload.debts), isTrue);
    });

    test('can be switched off', () {
      expect(_plan(now: morning, settings: const ReminderSettings(enabled: false, debts: false), debts: [owed]), isEmpty);
    });
  });

  test('never schedules more than the phone allows, in time order, with unique ids', () {
    final bills = [for (var i = 0; i < 40; i++) _bill('2026-12-${(i % 27 + 1).toString().padLeft(2, '0')}')];
    final plan = _plan(now: morning, recurring: bills);
    expect(plan.length, ReminderPlanner.maxPending);
    expect(plan.map((p) => p.id).toSet().length, plan.length);
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i].when.isBefore(plan[i - 1].when), isFalse);
    }
  });

  test('reminder settings round-trip and old profiles get the defaults', () {
    const s = ReminderSettings(enabled: false, hour: 7, minute: 15, bills: false, debts: true, budgetAlerts: false, dueHour: 18);
    final back = ReminderSettings.fromMap(s.toMap());
    expect((back.enabled, back.hour, back.minute, back.bills, back.debts, back.budgetAlerts, back.dueHour), (false, 7, 15, false, true, false, 18));
    final old = ReminderSettings.fromMap({'enabled': true, 'hour': 21, 'minute': 0});
    expect((old.bills, old.debts, old.budgetAlerts, old.dueHour), (true, true, true, 9));
  });
}
