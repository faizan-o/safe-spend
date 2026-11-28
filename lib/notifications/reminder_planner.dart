import '../logic/dues.dart';
import '../models/date_keys.dart';
import '../models/debt.dart';
import '../models/recurring.dart';
import '../models/user_profile.dart';
import '../utils/formatters.dart';

/// Which settings switch and Android channel a reminder belongs to.
enum ReminderChannel { daily, bills, budget }

/// What opens when a notification is tapped.
class ReminderPayload {
  const ReminderPayload._();

  static const daily = 'daily'; // the Voice tab, to log spending
  static const bills = 'bills'; // the Bills tab
  static const debts = 'debts'; // the Debts tab
  static const budget = 'budget'; // the Dashboard
}

/// One notification to be shown at a set time.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    required this.channel,
    required this.payload,
  });

  final int id;
  final DateTime when;
  final String title;
  final String body;
  final ReminderChannel channel;
  final String payload;

  /// A string that changes when anything about the reminder changes.
  String get signature => '$id|${when.millisecondsSinceEpoch}|$title|$body|$payload';
}

/// Works out which reminders should be scheduled, from the user's data.
///
/// It is pure (no phone APIs), so it is easy to test. The app re-runs it
/// whenever the data changes and replaces everything that was scheduled, so
/// a paid bill or an edited date can never leave a stale reminder behind.
class ReminderPlanner {
  const ReminderPlanner._();

  /// Phones limit pending notifications (iOS allows 64), so only the next
  /// ones are scheduled; the plan is rebuilt each time the app opens.
  static const int maxPending = 60;

  /// How many days of the daily reminder are scheduled ahead.
  static const int dailyDays = 14;

  /// How far ahead repeating bills are looked at.
  static const int billHorizonDays = 35;

  static List<PlannedReminder> plan({
    required DateTime now,
    required ReminderSettings settings,
    required String symbol,
    required List<RecurringItem> recurring,
    required List<Debt> debts,
    bool loggedToday = false,
    int spentToday = 0,
  }) {
    final today = DateKeys.startOfDay(now);
    final raw = <_Raw>[];

    // ---- Daily "log your spending" ---------------------------------------
    if (settings.enabled) {
      for (var i = 0; i < dailyDays; i++) {
        final day = DateKeys.addDays(today, i);
        final when = DateTime(day.year, day.month, day.day, settings.hour, settings.minute);
        if (!when.isAfter(now)) continue;
        if (i == 0 && loggedToday) continue; // already did it today
        final String title;
        final String body;
        if (i == 0 && spentToday > 0) {
          title = 'You spent ${formatMoney(spentToday, symbol)} today';
          body = 'Anything missing? Add it by voice in a few seconds.';
        } else {
          final variant = _dailyMessages[(day.day + day.month) % _dailyMessages.length];
          title = variant.$1;
          body = variant.$2;
        }
        raw.add(_Raw(when, title, body, ReminderChannel.daily, ReminderPayload.daily));
      }
    }

    // ---- Bills, income, debts and loans with a due date -------------------
    final dues = Dues.build(recurring: recurring, debts: debts, today: today);
    for (final item in dues) {
      final isDebt = item.debt != null;
      if (isDebt && !settings.debts) continue;
      if (!isDebt && !settings.bills) continue;
      final remind = item.recurring?.remindDays ?? 3;
      final payload = isDebt ? ReminderPayload.debts : ReminderPayload.bills;

      // The upcoming due dates: the next one, then the ones after it.
      final dates = <DateTime>[item.due];
      final r = item.recurring;
      if (r != null) {
        var last = item.due;
        while (dates.length < 4) {
          final next = r.dueAfter(last);
          if (next == null || DateKeys.daysBetween(today, next) > billHorizonDays) break;
          dates.add(next);
          last = next;
        }
      }

      for (final date in dates) {
        final days = DateKeys.daysBetween(today, date);
        if (days < 0) continue; // overdue is handled below
        DateTime at(int daysBefore) {
          final d = DateKeys.addDays(date, -daysBefore);
          return DateTime(d.year, d.month, d.day, settings.dueHour);
        }

        if (remind > 0) {
          final when = at(remind);
          if (when.isAfter(now)) {
            raw.add(_Raw(when, _title(item, remind), _body(item, symbol), ReminderChannel.bills, payload));
          }
        }
        final dueWhen = at(0);
        if (dueWhen.isAfter(now)) {
          raw.add(_Raw(dueWhen, _title(item, 0), _body(item, symbol), ReminderChannel.bills, payload));
        }
      }

      // Overdue: one nudge a day for the next three days.
      if (item.daysUntil < 0) {
        for (var k = 0; k < 3; k++) {
          final day = DateKeys.addDays(today, k);
          final when = DateTime(day.year, day.month, day.day, settings.dueHour);
          if (!when.isAfter(now)) continue;
          raw.add(_Raw(when, _title(item, item.daysUntil - k), _body(item, symbol), ReminderChannel.bills, payload));
        }
      }
    }

    raw.sort((a, b) => a.when.compareTo(b.when));
    final kept = raw.length > maxPending ? raw.sublist(0, maxPending) : raw;
    return [
      for (var i = 0; i < kept.length; i++)
        PlannedReminder(
          id: i + 1,
          when: kept[i].when,
          title: kept[i].title,
          body: kept[i].body,
          channel: kept[i].channel,
          payload: kept[i].payload,
        ),
    ];
  }

  /// "in 3 days", "tomorrow", "today", "2 days overdue".
  static String when(int days) {
    if (days < 0) return '${-days} ${-days == 1 ? 'day' : 'days'} overdue';
    if (days == 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  static String _title(DueItem item, int days) {
    final w = when(days);
    switch (item.kind) {
      case DueKind.bill:
        return days < 0 ? '${item.title} is $w' : '${item.title} is due $w';
      case DueKind.income:
        return days < 0 ? '${item.title} is $w' : '${item.title} is expected $w';
      case DueKind.debtToPay:
        return days < 0 ? 'Repayment to ${item.title} is $w' : 'Repay ${item.title} $w';
      case DueKind.loanToCollect:
        return days < 0 ? '${item.title}\'s repayment is $w' : '${item.title} should repay you $w';
    }
  }

  static String _body(DueItem item, String symbol) {
    final amount = formatMoney(item.amount, symbol);
    switch (item.kind) {
      case DueKind.bill:
        return '$amount. Open Bills to mark it paid.';
      case DueKind.income:
        return '$amount. Record it when it arrives.';
      case DueKind.debtToPay:
        return '$amount left to repay.';
      case DueKind.loanToCollect:
        return '$amount still to collect.';
    }
  }

  static const List<(String, String)> _dailyMessages = [
    ('Log today\'s spending', 'It takes 10 seconds. Just say what you bought.'),
    ('How did today go?', 'Add anything you paid for today so your safe-to-spend stays right.'),
    ('Quick money check-in', 'Note down today\'s expenses before you forget them.'),
    ('Did you spend anything today?', 'Say it or snap the receipt, and it is recorded.'),
  ];
}

class _Raw {
  const _Raw(this.when, this.title, this.body, this.channel, this.payload);

  final DateTime when;
  final String title;
  final String body;
  final ReminderChannel channel;
  final String payload;
}
