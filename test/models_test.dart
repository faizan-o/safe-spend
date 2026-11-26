import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/models/category.dart';
import 'package:safespend/models/expense.dart';
import 'package:safespend/models/month_stats.dart';
import 'package:safespend/models/month_summary.dart';
import 'package:safespend/models/monthly_budget.dart';
import 'package:safespend/models/money.dart';
import 'package:safespend/models/user_profile.dart';

void main() {
  group('Expense', () {
    test('survives a round trip through its map', () {
      final expense = Expense(
        amount: Money.fromMajor(500),
        categoryId: 'food',
        categoryName: 'Food & dining',
        categoryKind: CategoryKind.flexible,
        note: 'lunch',
        date: DateTime(2026, 11, 26, 13, 0),
        source: ExpenseSource.voice,
        transcript: '500 on lunch',
      );

      final map = expense.toMap();
      expect(map['dayKey'], '2026-11-26');
      expect(map['monthKey'], '2026-11');
      expect(map['source'], 'voice');

      final copy = Expense.fromMap('abc', map);
      expect(copy.id, 'abc');
      expect(copy.amount, 50000);
      expect(copy.categoryId, 'food');
      expect(copy.categoryKind, CategoryKind.flexible);
      expect(copy.note, 'lunch');
      expect(copy.date, DateTime(2026, 11, 26, 13, 0));
      expect(copy.source, ExpenseSource.voice);
      expect(copy.transcript, '500 on lunch');
    });

    test('falls back safely when fields are missing', () {
      final expense = Expense.fromMap('x', const {});
      expect(expense.amount, 0);
      expect(expense.categoryKind, CategoryKind.flexible);
      expect(expense.source, ExpenseSource.manual);
      expect(expense.transcript, isNull);
    });
  });

  group('MonthlyBudget', () {
    CategoryBudget line(String id, CategoryKind kind, int rupees) => CategoryBudget(
          categoryId: id,
          name: id,
          iconKey: 'category',
          colorValue: 0xFF000000,
          kind: kind,
          limit: Money.fromMajor(rupees),
        );

    final budget = MonthlyBudget(
      monthKey: '2026-11',
      income: Money.fromMajor(60000),
      categories: [
        line('rent', CategoryKind.fixed, 25000),
        line('savings', CategoryKind.savings, 10000),
        line('food', CategoryKind.flexible, 10000),
        line('transport', CategoryKind.flexible, 5000),
      ],
    );

    test('splits income into fixed, savings and flexible money', () {
      expect(budget.totalFixed, Money.fromMajor(25000));
      expect(budget.savingsGoal, Money.fromMajor(10000));
      expect(budget.flexiblePool, Money.fromMajor(25000));
      expect(budget.flexibleLimits, Money.fromMajor(15000));
      expect(budget.unallocated, Money.fromMajor(10000));
    });

    test('survives a round trip through its map', () {
      final copy = MonthlyBudget.fromMap('2026-11', budget.toMap());
      expect(copy.income, budget.income);
      expect(copy.categories.length, 4);
      expect(copy.forCategory('food')?.limit, Money.fromMajor(10000));
      expect(copy.forCategory('missing'), isNull);
    });

    test('copyWith can move a budget to another month', () {
      final next = budget.copyWith(monthKey: '2026-12');
      expect(next.monthKey, '2026-12');
      expect(next.income, budget.income);
    });
  });

  group('MonthStats', () {
    test('reads nested totals', () {
      final stats = MonthStats.fromMap('2026-11', {
        'totalSpent': 900000,
        'flexibleSpent': 400000,
        'expenseCount': 7,
        'spentByCategory': {'food': 250000, 'rent': 500000},
        'spentByDay': {'05': 300000, '26': 600000},
      });
      expect(stats.totalSpent, 900000);
      expect(stats.spentIn('food'), 250000);
      expect(stats.spentIn('other'), 0);
      expect(stats.spentOnDay(DateTime(2026, 11, 5)), 300000);
      expect(stats.spentOnDay(DateTime(2026, 11, 6)), 0);
    });

    test('an empty document reads as all zeros', () {
      final stats = MonthStats.fromMap('2026-11', const {});
      expect(stats.totalSpent, 0);
      expect(stats.expenseCount, 0);
      expect(stats.spentByCategory, isEmpty);
    });
  });

  group('MonthSummary', () {
    test('separates red and green flags and round-trips', () {
      const summary = MonthSummary(
        monthKey: '2026-11',
        income: 6000000,
        totalSpent: 4000000,
        flexibleSpent: 1500000,
        saved: 1000000,
        suggestion: 'Lower the food budget by Rs. 1,000.',
        categories: [
          CategoryResult(categoryId: 'food', name: 'Food', limit: 1000000, spent: 1400000, flag: FlagType.red),
          CategoryResult(categoryId: 'transport', name: 'Transport', limit: 500000, spent: 200000, flag: FlagType.green),
          CategoryResult(categoryId: 'other', name: 'Other', limit: 300000, spent: 290000),
        ],
      );
      expect(summary.redFlags.single.categoryId, 'food');
      expect(summary.greenFlags.single.categoryId, 'transport');
      expect(summary.categories.first.usedRatio, closeTo(1.4, 0.0001));

      final copy = MonthSummary.fromMap('2026-11', summary.toMap());
      expect(copy.categories.length, 3);
      expect(copy.categories.first.flag, FlagType.red);
      expect(copy.suggestion, summary.suggestion);
    });
  });

  group('UserProfile', () {
    test('round-trips and applies defaults', () {
      const profile = UserProfile(uid: 'u1', name: 'Faizan', email: 'f@example.com');
      final copy = UserProfile.fromMap('u1', profile.toMap());
      expect(copy.currencyCode, 'PKR');
      expect(copy.currencySymbol, 'Rs.');
      expect(copy.reminder.enabled, isTrue);
      expect(copy.reminder.hour, 21);
      expect(copy.onboardingComplete, isFalse);
    });
  });

  test('default categories have unique ids and one savings category', () {
    final ids = defaultCategories.map((c) => c.id).toSet();
    expect(ids.length, defaultCategories.length);
    expect(defaultCategories.where((c) => c.kind == CategoryKind.savings).length, 1);
    expect(defaultCategories.where((c) => c.kind == CategoryKind.fixed), isNotEmpty);
  });
}
