import 'dart:math';

import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/debt.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/monthly_budget.dart';
import '../models/recurring.dart';
import 'user_data.dart';

/// Fills an account with realistic test data: last month (the whole month) and
/// this month so far, with a budget for each and a few days of overspending,
/// so the dashboard, flags and the monthly report have something to show.
///
/// Nothing here is special in the database: they are ordinary expenses saved
/// the same way as typed ones, so the month totals stay correct. Delete them
/// again with "Delete all my data" if needed.
class SampleData {
  const SampleData._();

  static const int _paisa = 100;

  /// Returns how many expenses were added. [onProgress] gets (done, total).
  static Future<int> load(
    UserData data, {
    DateTime? now,
    void Function(int done, int total)? onProgress,
  }) async {
    final today = now ?? DateTime.now();
    final categories = await data.categories.getCategories();
    final byId = {for (final c in categories) c.id: c};
    if (byId.isEmpty) throw StateError('No categories yet. Open the Dashboard once, then try again.');

    final firstOfThisMonth = DateTime(today.year, today.month);
    final firstOfLastMonth = DateTime(today.year, today.month - 1);
    final months = [firstOfLastMonth, firstOfThisMonth];

    // Budgets (kept if the user already has one).
    for (final month in months) {
      final key = DateKeys.ofMonth(month);
      if (await data.budgets.getBudget(key) == null) {
        await data.budgets.saveBudget(_budget(key, categories));
      }
    }

    await _addMoneyExtras(data, categories, today, months);

    // Expenses.
    final random = Random(2026);
    final plan = <Expense>[];
    for (final month in months) {
      final isLast = month == firstOfLastMonth;
      final days = isLast ? _Days.daysIn(month) : today.day;
      for (var day = 1; day <= days; day++) {
        final date = DateTime(month.year, month.month, day);
        plan.addAll(_fixedFor(date, byId, isLast));
        plan.addAll(_everydayFor(date, byId, random, isLast));
      }
    }

    var done = 0;
    for (final expense in plan) {
      if (expense.date.isAfter(today)) continue;
      await data.expenses.addExpense(expense);
      done++;
      onProgress?.call(done, plan.length);
    }
    return done;
  }

  /// An opening balance, a salary each month, a few bills with due dates and
  /// one debt and one loan. Skipped for anything the user already has.
  static Future<void> _addMoneyExtras(
    UserData data,
    List<ExpenseCategory> categories,
    DateTime today,
    List<DateTime> months,
  ) async {
    final profile = await data.profile.watchProfile().first;
    if (profile != null && !profile.hasOpeningBalance) {
      await data.profile.updateOpeningBalance(amount: 60000 * _paisa, day: months.first);
    }

    for (final month in months) {
      final date = DateTime(month.year, month.month, 1, 9);
      if (date.isAfter(today)) continue;
      await data.incomes.addIncome(Income(
        amount: 150000 * _paisa,
        source: 'Salary',
        note: 'Monthly salary',
        date: date,
      ));
    }

    if ((await data.recurring.getAll()).isEmpty) {
      DateTime next(int day) {
        final thisMonth = DateTime(today.year, today.month, day);
        return thisMonth.isBefore(DateKeys.startOfDay(today)) ? DateTime(today.year, today.month + 1, day) : thisMonth;
      }

      ExpenseCategory? find(String id) {
        for (final c in categories) {
          if (c.id == id) return c;
        }
        return null;
      }

      RecurringItem bill(String title, int rupees, String categoryId, int day, {int remind = 3}) {
        final category = find(categoryId);
        final due = next(day);
        return RecurringItem(
          title: title,
          amount: rupees * _paisa,
          categoryId: category?.id,
          categoryName: category?.name,
          categoryKind: category?.kind,
          startDay: DateKeys.ofDay(due),
          nextDueDay: DateKeys.ofDay(due),
          remindDays: remind,
        );
      }

      await data.recurring.add(bill('Rent', 40000, 'rent', 3, remind: 5));
      await data.recurring.add(bill('Electricity', 12000, 'bills', 8));
      await data.recurring.add(bill('Internet', 3500, 'bills', 14));
    }

    if ((await data.debts.watchAll().first).isEmpty) {
      final soon = DateKeys.addDays(DateKeys.startOfDay(today), 6);
      await data.debts.add(Debt(
        direction: DebtDirection.owedByMe,
        person: 'Ali (borrowed)',
        amount: 15000 * _paisa,
        date: DateKeys.addDays(today, -20),
        dueDay: DateKeys.ofDay(soon),
        note: 'For the phone repair',
      ));
      await data.debts.add(Debt(
        direction: DebtDirection.owedToMe,
        person: 'Sara (lent)',
        amount: 8000 * _paisa,
        date: DateKeys.addDays(today, -10),
        dueDay: DateKeys.ofDay(DateKeys.addDays(DateKeys.startOfDay(today), -2)),
        note: 'Lent for the trip',
      ));
    }
  }

  static MonthlyBudget _budget(String monthKey, List<ExpenseCategory> categories) {
    const limits = <String, int>{
      'rent': 40000,
      'bills': 12000,
      'committee': 10000,
      'savings': 20000,
      'food': 18000,
      'groceries': 15000,
      'transport': 8000,
      'shopping': 8000,
      'entertainment': 5000,
      'health': 5000,
      'education': 4000,
      'other': 3000,
    };
    return MonthlyBudget(
      monthKey: monthKey,
      income: 150000 * _paisa,
      categories: [
        for (final c in categories)
          if (limits.containsKey(c.id)) CategoryBudget.fromCategory(c, limits[c.id]! * _paisa),
      ],
    );
  }

  /// Rent, bills, committee and savings on their usual days.
  static List<Expense> _fixedFor(DateTime date, Map<String, ExpenseCategory> byId, bool isLast) {
    Expense? make(String id, int rupees, String note, {String? merchant}) {
      final c = byId[id];
      if (c == null) return null;
      return Expense(
        amount: rupees * _paisa,
        categoryId: c.id,
        categoryName: c.name,
        categoryKind: c.kind,
        note: note,
        merchant: merchant,
        date: DateTime(date.year, date.month, date.day, 10),
      );
    }

    return [
      if (date.day == 3) make('rent', 40000, 'Monthly rent'),
      if (date.day == 8) make('bills', isLast ? 13200 : 11800, 'Electricity and gas', merchant: 'IESCO'),
      if (date.day == 12) make('committee', 10000, 'Committee installment'),
      if (date.day == 20) make('savings', 15000, 'Moved to savings'),
    ].whereType<Expense>().toList();
  }

  /// A few ordinary expenses per day. Last month is made to overspend on
  /// Entertainment and Shopping and underspend on Transport.
  static List<Expense> _everydayFor(
    DateTime date,
    Map<String, ExpenseCategory> byId,
    Random random,
    bool isLast,
  ) {
    final out = <Expense>[];

    void add(String id, int low, int high, List<String> notes, {List<String> shops = const []}) {
      final c = byId[id];
      if (c == null) return;
      final rupees = ((low + random.nextInt(high - low + 1)) / 10).round() * 10;
      out.add(Expense(
        amount: rupees * _paisa,
        categoryId: c.id,
        categoryName: c.name,
        categoryKind: c.kind,
        note: notes[random.nextInt(notes.length)],
        merchant: shops.isEmpty ? null : shops[random.nextInt(shops.length)],
        date: DateTime(date.year, date.month, date.day, 9 + random.nextInt(12), random.nextInt(60)),
      ));
    }

    final weekend = date.weekday >= 5;

    // Lunch on most days, dinner out more often at weekends.
    if (random.nextInt(10) < 8) add('food', 250, 700, ['Lunch', 'Lunch with friends', 'Chai and snacks']);
    if (weekend && random.nextInt(10) < 7) add('food', 800, 2200, ['Dinner out', 'Biryani', 'Pizza'], shops: ['Savour Foods', 'Kababjees', 'Pizza Hut']);

    if (date.weekday == 6) add('groceries', 2200, 4500, ['Weekly groceries'], shops: ['Imtiaz store', 'Metro', 'Al-Fatah']);
    if (random.nextInt(10) < 2) add('groceries', 300, 900, ['Milk and eggs', 'Vegetables', 'Fruit']);

    // Transport: cheaper last month (an underspent category).
    if (!weekend && random.nextInt(10) < (isLast ? 3 : 6)) add('transport', 150, isLast ? 350 : 600, ['Careem', 'Fuel', 'Rickshaw']);

    // Entertainment and shopping: overspent last month.
    if (random.nextInt(10) < (isLast ? 3 : 1)) add('entertainment', 600, isLast ? 2200 : 1200, ['Movie', 'Netflix', 'Games']);
    if (random.nextInt(14) < (isLast ? 2 : 1)) add('shopping', 1500, isLast ? 4800 : 2500, ['Clothes', 'Shoes', 'New bag'], shops: ['Khaadi', 'Outfitters', 'Daraz']);

    if (random.nextInt(25) == 0) add('health', 400, 1800, ['Pharmacy', 'Doctor visit']);
    if (date.day == 15) add('education', 1500, 3000, ['Books', 'Course fee']);
    if (random.nextInt(20) == 0) add('other', 200, 900, ['Gift', 'Miscellaneous']);

    return out;
  }
}

/// Small date helpers used by the sample data.
class _Days {
  const _Days._();

  static int daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;
}
