import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/logic/budget_calculator.dart';
import 'package:safespend/models/category.dart';
import 'package:safespend/models/month_stats.dart';
import 'package:safespend/models/month_summary.dart' show FlagType;
import 'package:safespend/models/monthly_budget.dart';

CategoryBudget _line(String id, CategoryKind kind, int limit) => CategoryBudget(
      categoryId: id,
      name: id,
      iconKey: 'category',
      colorValue: 0xFF000000,
      kind: kind,
      limit: limit,
    );

void main() {
  group('DailyBudget', () {
    test('divides what is left by the days remaining', () {
      const daily = DailyBudget(
        pool: 2500000,
        spentBeforeToday: 800000,
        spentToday: 50000,
        daysLeft: 20,
      );
      expect(daily.allowanceToday, 85000);
      expect(daily.leftToday, 35000);
      expect(daily.remainingPool, 1650000);
      expect(daily.usedFraction, closeTo(50000 / 85000, 0.0001));
      expect(daily.status, DayStatus.onTrack);
    });

    test('is tight when under a quarter of the allowance is left', () {
      const daily = DailyBudget(
        pool: 2500000,
        spentBeforeToday: 800000,
        spentToday: 70000,
        daysLeft: 20,
      );
      expect(daily.leftToday, 15000);
      expect(daily.status, DayStatus.tight);
    });

    test('is over when today passes the allowance', () {
      const daily = DailyBudget(
        pool: 2500000,
        spentBeforeToday: 800000,
        spentToday: 100000,
        daysLeft: 20,
      );
      expect(daily.leftToday, -15000);
      expect(daily.usedFraction, 1);
      expect(daily.status, DayStatus.over);
    });

    test('has no allowance once the month is overspent', () {
      const daily = DailyBudget(
        pool: 100,
        spentBeforeToday: 200,
        spentToday: 0,
        daysLeft: 10,
      );
      expect(daily.allowanceToday, 0);
      expect(daily.remainingPool, -100);
      expect(daily.status, DayStatus.over);
    });

    test('a quiet day raises tomorrow, a heavy day lowers it', () {
      const quiet = DailyBudget(pool: 3000000, spentBeforeToday: 0, spentToday: 0, daysLeft: 30);
      final nextAfterQuiet = const DailyBudget(
        pool: 3000000,
        spentBeforeToday: 0,
        spentToday: 0,
        daysLeft: 29,
      );
      final nextAfterHeavy = const DailyBudget(
        pool: 3000000,
        spentBeforeToday: 500000,
        spentToday: 0,
        daysLeft: 29,
      );
      expect(nextAfterQuiet.allowanceToday, greaterThan(quiet.allowanceToday));
      expect(nextAfterHeavy.allowanceToday, lessThan(quiet.allowanceToday));
    });
  });

  group('BudgetCalculator.dailyBudget', () {
    test('builds today\'s numbers from the budget and the month totals', () {
      final budget = MonthlyBudget(
        monthKey: '2026-11',
        income: 6000000,
        categories: [
          _line('rent', CategoryKind.fixed, 2500000),
          _line('savings', CategoryKind.savings, 1000000),
          _line('food', CategoryKind.flexible, 1500000),
        ],
      );
      const stats = MonthStats(monthKey: '2026-11', flexibleSpent: 850000);

      final daily = BudgetCalculator.dailyBudget(
        budget: budget,
        stats: stats,
        spentToday: 50000,
        now: DateTime(2026, 11, 11),
      );

      expect(daily.pool, 2500000);
      expect(daily.spentBeforeToday, 800000);
      expect(daily.daysLeft, 20);
      expect(daily.allowanceToday, 85000);
    });

    test('counts today as a remaining day on the last day of the month', () {
      final budget = MonthlyBudget(monthKey: '2026-11', income: 1000000);
      final daily = BudgetCalculator.dailyBudget(
        budget: budget,
        stats: const MonthStats(monthKey: '2026-11'),
        spentToday: 0,
        now: DateTime(2026, 11, 30),
      );
      expect(daily.daysLeft, 1);
    });
  });

  group('BudgetCalculator.flagFor', () {
    final food = _line('food', CategoryKind.flexible, 1000000);
    final midMonth = DateTime(2026, 11, 15); // expected spend so far: 500000

    test('red when well ahead of an even pace', () {
      expect(BudgetCalculator.flagFor(line: food, spent: 600000, now: midMonth), FlagType.red);
    });

    test('green when well behind an even pace', () {
      expect(BudgetCalculator.flagFor(line: food, spent: 400000, now: midMonth), FlagType.green);
    });

    test('no flag when close to pace', () {
      expect(BudgetCalculator.flagFor(line: food, spent: 500000, now: midMonth), FlagType.none);
    });

    test('pace flags wait until day 5, but going over the limit is always red', () {
      final early = DateTime(2026, 11, 3);
      expect(BudgetCalculator.flagFor(line: food, spent: 900000, now: early), FlagType.none);
      expect(BudgetCalculator.flagFor(line: food, spent: 1100000, now: early), FlagType.red);
    });

    test('only everyday categories with a limit are flagged', () {
      final rent = _line('rent', CategoryKind.fixed, 1000000);
      final none = _line('misc', CategoryKind.flexible, 0);
      expect(BudgetCalculator.flagFor(line: rent, spent: 2000000, now: midMonth), FlagType.none);
      expect(BudgetCalculator.flagFor(line: none, spent: 50000, now: midMonth), FlagType.none);
    });

    test('at month end the pace is the whole limit', () {
      final end = DateTime(2026, 11, 30);
      expect(BudgetCalculator.flagFor(line: food, spent: 1050000, now: end), FlagType.red);
      expect(BudgetCalculator.flagFor(line: food, spent: 800000, now: end), FlagType.green);
      expect(BudgetCalculator.flagFor(line: food, spent: 950000, now: end), FlagType.none);
    });
  });

  test('expectedSpend follows the day of the month', () {
    final food = _line('food', CategoryKind.flexible, 3000000);
    expect(BudgetCalculator.expectedSpend(food, DateTime(2026, 11, 10)), 1000000);
    expect(BudgetCalculator.expectedSpend(food, DateTime(2026, 11, 30)), 3000000);
  });

  test('unbudgetedSpent adds up categories missing from the budget', () {
    final budget = MonthlyBudget(
      monthKey: '2026-11',
      income: 1000000,
      categories: [_line('food', CategoryKind.flexible, 500000)],
    );
    const stats = MonthStats(
      monthKey: '2026-11',
      spentByCategory: {'food': 100000, 'other': 250000, 'gift': 50000},
    );
    expect(BudgetCalculator.unbudgetedSpent(budget, stats), 300000);
  });
}
