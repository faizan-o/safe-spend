import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/logic/activity.dart';
import 'package:safespend/logic/balance_calculator.dart';
import 'package:safespend/logic/dues.dart';
import 'package:safespend/models/budget_period.dart';
import 'package:safespend/models/debt.dart';
import 'package:safespend/models/expense.dart';
import 'package:safespend/models/income.dart';
import 'package:safespend/models/month_stats.dart';
import 'package:safespend/models/recurring.dart';
import 'package:safespend/models/user_profile.dart';
import 'package:safespend/models/category.dart';

RecurringItem _bill(String due, {Frequency frequency = Frequency.monthly, String? start, String? end, int interval = 1}) {
  return RecurringItem(
    title: 'Rent',
    amount: 4000000,
    startDay: start ?? due,
    nextDueDay: due,
    frequency: frequency,
    interval: interval,
    endDay: end,
  );
}

void main() {
  group('BudgetPeriod', () {
    test('a weekly budget runs Monday to Sunday', () {
      final start = BudgetPeriod.defaultStart(PeriodType.weekly, DateTime(2026, 11, 26)); // Thursday
      expect(start, DateTime(2026, 11, 23));
      final period = BudgetPeriod.starting(PeriodType.weekly, start);
      expect(period.endDay, '2026-11-29');
      expect(period.totalDays, 7);
    });

    test('a yearly budget covers the calendar year', () {
      final period = BudgetPeriod.starting(PeriodType.yearly, DateTime(2026, 1, 1));
      expect(period.endDay, '2026-12-31');
      expect(period.totalDays, 365);
    });

    test('counts days and what is left', () {
      final period = BudgetPeriod.month('2026-11');
      expect(period.isCalendarMonth, isTrue);
      expect(period.dayNumber(DateTime(2026, 11, 1)), 1);
      expect(period.daysLeft(DateTime(2026, 11, 26)), 5);
      expect(period.contains(DateTime(2026, 12, 1)), isFalse);
      expect(period.hasEnded(DateTime(2026, 12, 1)), isTrue);
    });

    test('a custom period of 10 days repeats its own length', () {
      final period = BudgetPeriod(type: PeriodType.custom, start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 10));
      final next = period.following();
      expect(next.startDay, '2026-11-11');
      expect(next.endDay, '2026-11-20');
      expect(period.advancedTo(DateTime(2026, 11, 25)).startDay, '2026-11-21');
    });
  });

  group('RecurringItem', () {
    test('a monthly bill keeps its day of the month', () {
      final item = _bill('2026-01-31', start: '2026-01-31');
      expect(dayKeyOf(item.dueAfter(DateTime(2026, 1, 31))!), '2026-02-28');
      expect(dayKeyOf(item.dueAfter(DateTime(2026, 2, 28))!), '2026-03-31');
    });

    test('weekly with an interval of 2 moves a fortnight', () {
      final item = _bill('2026-11-02', frequency: Frequency.weekly, interval: 2);
      expect(dayKeyOf(item.dueAfter(DateTime(2026, 11, 2))!), '2026-11-16');
    });

    test('a one-time bill has no next date', () {
      expect(_bill('2026-11-02', frequency: Frequency.once).dueAfter(DateTime(2026, 11, 2)), isNull);
    });

    test('stops after its end date', () {
      final item = _bill('2026-11-03', end: '2026-12-31');
      expect(item.dueAfter(DateTime(2026, 11, 3)), DateTime(2026, 12, 3));
      expect(item.dueAfter(DateTime(2026, 12, 3)), isNull);
    });

    test('lists every missed due date up to today', () {
      final item = _bill('2026-09-03');
      final dues = item.duesUpTo(DateTime(2026, 11, 26));
      expect(dues.map(dayKeyOf).toList(), ['2026-09-03', '2026-10-03', '2026-11-03']);
    });

    test('overdue and due soon', () {
      final item = _bill('2026-11-28');
      expect(item.isDueSoon(DateTime(2026, 11, 26)), isTrue); // within 3 days
      expect(item.isOverdue(DateTime(2026, 11, 26)), isFalse);
      expect(item.isOverdue(DateTime(2026, 11, 30)), isTrue);
      expect(item.daysUntilDue(DateTime(2026, 11, 26)), 2);
    });

    test('survives a round trip through its map', () {
      final item = _bill('2026-11-28', end: '2027-01-01');
      final copy = RecurringItem.fromMap('id1', item.toMap());
      expect(copy.id, 'id1');
      expect(copy.title, 'Rent');
      expect(copy.amount, 4000000);
      expect(copy.nextDueDay, '2026-11-28');
      expect(copy.endDay, '2027-01-01');
      expect(copy.frequency, Frequency.monthly);
    });
  });

  group('Debt', () {
    Debt debt({DebtDirection direction = DebtDirection.owedByMe, String? due, List<DebtPayment> payments = const []}) {
      return Debt(
        direction: direction,
        person: 'Ali',
        amount: 1500000,
        date: DateTime(2026, 11, 1),
        dueDay: due,
        payments: payments,
      );
    }

    test('tracks what is repaid and what is left', () {
      final d = debt(payments: [DebtPayment(id: 'a', amount: 500000, date: DateTime(2026, 11, 5))]);
      expect(d.paid, 500000);
      expect(d.remaining, 1000000);
      expect(d.isSettled, isFalse);
      expect(d.progress, closeTo(1 / 3, 0.0001));
    });

    test('is settled once fully repaid', () {
      final d = debt(payments: [DebtPayment(id: 'a', amount: 1500000, date: DateTime(2026, 11, 5))]);
      expect(d.isSettled, isTrue);
      expect(d.remaining, 0);
    });

    test('overdue only while unpaid and past its due day', () {
      expect(debt(due: '2026-11-20').isOverdue(DateTime(2026, 11, 26)), isTrue);
      expect(debt().isOverdue(DateTime(2026, 11, 26)), isFalse);
      expect(debt(due: '2026-11-20').daysUntilDue(DateTime(2026, 11, 26)), -6);
    });

    test('survives a round trip through its map', () {
      final d = debt(
        direction: DebtDirection.owedToMe,
        due: '2026-12-01',
        payments: [DebtPayment(id: 'a', amount: 100, date: DateTime(2026, 11, 5), note: 'part')],
      );
      final map = d.toMap();
      expect(map['paidTotal'], 100);
      final copy = Debt.fromMap('d1', map);
      expect(copy.isOwedToMe, isTrue);
      expect(copy.dueDay, '2026-12-01');
      expect(copy.payments.single.note, 'part');
    });
  });

  group('BalanceCalculator', () {
    const profile = UserProfile(
      uid: 'u',
      name: 'A',
      email: 'a@b.c',
      openingBalance: 10000000,
      openingBalanceDay: '2026-11-10',
    );

    test('is null before an opening balance is set', () {
      const none = UserProfile(uid: 'u', name: 'A', email: 'a@b.c');
      expect(BalanceCalculator.compute(profile: none, stats: const [], debts: const []), isNull);
    });

    test('adds income and takes off spending from the opening day on', () {
      final stats = [
        const MonthStats(
          monthKey: '2026-11',
          totalSpent: 900000,
          spentByDay: {'05': 400000, '10': 300000, '20': 200000},
          totalIncome: 5000000,
          incomeByDay: {'01': 5000000},
        ),
        const MonthStats(monthKey: '2026-12', totalSpent: 100000, totalIncome: 200000),
        // Before the opening month: ignored.
        const MonthStats(monthKey: '2026-10', totalSpent: 777, totalIncome: 888),
      ];
      final summary = BalanceCalculator.compute(profile: profile, stats: stats, debts: const [])!;
      expect(summary.spent, 300000 + 200000 + 100000);
      expect(summary.income, 200000); // the 1 Nov salary is before 10 Nov
      expect(summary.balance, 10000000 + 200000 - 600000);
    });

    test('borrowed money comes in and repayments go out', () {
      final debts = [
        Debt(
          direction: DebtDirection.owedByMe,
          person: 'Ali',
          amount: 1000000,
          date: DateTime(2026, 11, 12),
          payments: [DebtPayment(id: 'a', amount: 400000, date: DateTime(2026, 11, 15))],
        ),
      ];
      final summary = BalanceCalculator.compute(profile: profile, stats: const [], debts: debts)!;
      expect(summary.loansIn, 1000000);
      expect(summary.loansOut, 400000);
      expect(summary.balance, 10000000 + 600000);
    });

    test('lent money goes out and comes back as it is repaid', () {
      final debts = [
        Debt(
          direction: DebtDirection.owedToMe,
          person: 'Sara',
          amount: 800000,
          date: DateTime(2026, 11, 12),
          payments: [DebtPayment(id: 'a', amount: 300000, date: DateTime(2026, 11, 20))],
        ),
      ];
      final summary = BalanceCalculator.compute(profile: profile, stats: const [], debts: debts)!;
      expect(summary.balance, 10000000 - 800000 + 300000);
      expect(BalanceCalculator.totalLent(debts), 500000);
      expect(BalanceCalculator.totalOwed(debts), 0);
    });

    test('a debt that does not affect the balance is ignored', () {
      final debts = [
        Debt(
          direction: DebtDirection.owedByMe,
          person: 'Ali',
          amount: 1000000,
          date: DateTime(2026, 11, 12),
          affectsBalance: false,
        ),
      ];
      final summary = BalanceCalculator.compute(profile: profile, stats: const [], debts: debts)!;
      expect(summary.balance, 10000000);
    });
  });

  group('Dues', () {
    test('puts overdue first and leaves out paused bills and settled debts', () {
      final today = DateTime(2026, 11, 26);
      final recurring = [
        _bill('2026-12-03'),
        _bill('2026-11-20'),
        _bill('2026-11-28').copyWith(active: false),
      ];
      final debts = [
        Debt(
          direction: DebtDirection.owedToMe,
          person: 'Sara',
          amount: 100,
          date: DateTime(2026, 11, 1),
          dueDay: '2026-11-27',
        ),
        Debt(
          direction: DebtDirection.owedByMe,
          person: 'Done',
          amount: 100,
          date: DateTime(2026, 11, 1),
          dueDay: '2026-11-25',
          payments: [DebtPayment(id: 'a', amount: 100, date: DateTime(2026, 11, 2))],
        ),
      ];
      final dues = Dues.build(recurring: recurring, debts: debts, today: today);
      expect(dues.length, 3);
      expect(dues.first.overdue, isTrue);
      expect(dues.first.daysUntil, -6);
      expect(dues[1].kind, DueKind.loanToCollect);
      expect(dues[1].isMoneyIn, isTrue);
      expect(Dues.build(recurring: recurring, debts: debts, today: today, withinDays: 3).length, 2);
    });
  });

  group('ActivityItem', () {
    test('merges expenses and income, newest first', () {
      final expense = Expense(
        id: 'e1',
        amount: 100,
        categoryId: 'food',
        categoryName: 'Food',
        categoryKind: CategoryKind.flexible,
        date: DateTime(2026, 11, 26, 12),
      );
      final income = Income(id: 'i1', amount: 500, source: 'Salary', date: DateTime(2026, 11, 26, 15));
      final items = ActivityItem.merge([expense], [income]);
      expect(items.map((i) => i.id).toList(), ['i1', 'e1']);
      expect(items.first.signedAmount, 500);
      expect(items.last.signedAmount, -100);
      expect(ActivityItem.merge([expense], [income], limit: 1).length, 1);
    });
  });

  group('Income', () {
    test('survives a round trip through its map', () {
      final income = Income(amount: 500000, source: 'Freelance', note: 'logo', date: DateTime(2026, 11, 26, 9, 30));
      final map = income.toMap();
      expect(map['dayKey'], '2026-11-26');
      expect(map['monthKey'], '2026-11');
      final copy = Income.fromMap('x', map);
      expect(copy.amount, 500000);
      expect(copy.source, 'Freelance');
      expect(copy.date, DateTime(2026, 11, 26, 9, 30));
    });
  });
}

String dayKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
