import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/debt.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/month_stats.dart';
import '../models/month_summary.dart' show FlagType;
import '../models/monthly_budget.dart';
import '../models/recurring.dart';
import '../models/user_profile.dart';
import 'activity.dart';
import 'balance_calculator.dart';
import 'budget_calculator.dart';
import 'dues.dart';
import 'period_stats.dart';

/// One category line on the dashboard: its budget, what was spent and its flag.
class CategoryRow {
  const CategoryRow({
    required this.line,
    required this.spent,
    required this.flag,
  });

  final CategoryBudget line;
  final int spent;
  final FlagType flag;

  /// Share of the limit used (can be above 1).
  double get usedRatio => line.limit <= 0 ? 0 : spent / line.limit;
}

/// Holds everything the dashboard shows and keeps it live by listening to
/// Firestore. Widgets listen to this object and rebuild when anything changes.
///
/// The dashboard follows the budget that covers today (a week, a month, a
/// year or custom dates). When several budgets cover today, [selectBudget]
/// picks which one is shown; the newest one is the default.
class DashboardController extends ChangeNotifier {
  DashboardController(this.data) {
    _listen<UserProfile?>('profile', data.profile.watchProfile(), (value) => profile = value);
    _listen<List<ExpenseCategory>>('categories', data.categories.watchCategories(), (value) => categories = value);
    _listen<List<MonthlyBudget>>('budgets', data.budgets.watchBudgets(), (value) {
      budgets = value;
      _pickBudget();
    });
    _listen<List<MonthStats>>('allStats', data.expenses.watchAllStats(), (value) => allStats = value);
    _listen<List<Debt>>('debts', data.debts.watchAll(), (value) => debts = value);
    _listen<List<RecurringItem>>('recurring', data.recurring.watchAll(), (value) => recurring = value);
    _listen<List<Expense>>('recentExpenses', data.expenses.watchRecent(limit: 8), (value) => recentExpenses = value);
    _listen<List<Income>>('recentIncomes', data.incomes.watchRecent(limit: 8), (value) => recentIncomes = value);
  }

  static const int _streamCount = 8;

  final UserData data;

  UserProfile? profile;
  List<ExpenseCategory> categories = const [];

  /// Every budget, newest period first.
  List<MonthlyBudget> budgets = const [];

  /// The budget being shown: one that covers today, or null.
  MonthlyBudget? budget;

  /// Stored totals of every month; the balance is worked out from these.
  List<MonthStats> allStats = const [];
  List<Debt> debts = const [];
  List<RecurringItem> recurring = const [];
  List<Expense> recentExpenses = const [];
  List<Income> recentIncomes = const [];

  /// Expenses and income inside the shown budget's period.
  List<Expense> periodExpenses = const [];
  List<Income> periodIncomes = const [];
  MonthStats _stats = const MonthStats(monthKey: '');

  /// The id of the budget the user chose when several cover today.
  String? selectedBudgetId;

  /// The last error from any of the streams (for example missing security
  /// rules), or null.
  Object? error;

  final Set<String> _loaded = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<List<Expense>>? _expenseRange;
  StreamSubscription<List<Income>>? _incomeRange;
  String? _boundKey;
  bool _expensesLoaded = true;
  bool _incomesLoaded = true;
  bool _disposed = false;

  /// True until every stream has delivered its first value.
  bool get loading => _loaded.length < _streamCount || !_expensesLoaded || !_incomesLoaded;

  void _listen<T>(String name, Stream<T> stream, void Function(T value) apply) {
    _subscriptions.add(stream.listen(
      (value) {
        apply(value);
        _loaded.add(name);
        _notify();
      },
      onError: (Object e) {
        error = e;
        _loaded.add(name);
        _notify();
      },
    ));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- Which budget is shown ----------------------------------------------

  /// Budgets whose period includes today.
  List<MonthlyBudget> get activeBudgets {
    final today = DateTime.now();
    return [
      for (final b in budgets)
        if (b.period.contains(today)) b,
    ];
  }

  /// Shows the budget with this id (it must cover today).
  void selectBudget(String id) {
    selectedBudgetId = id;
    _pickBudget();
    _notify();
  }

  /// Call when the app comes back to the front: the day (and so the budget in
  /// force) may have changed.
  void refreshToday() {
    _pickBudget();
    _notify();
  }

  void _pickBudget() {
    final active = activeBudgets;
    MonthlyBudget? chosen;
    for (final b in active) {
      if (b.id == selectedBudgetId) chosen = b;
    }
    chosen ??= active.isEmpty ? null : active.first;
    budget = chosen;
    _bindRange();
  }

  /// Follows the expenses and income of the shown budget's period. Does
  /// nothing when the budget's id and dates are unchanged.
  void _bindRange() {
    final current = budget;
    final key = current == null ? null : '${current.id}|${current.period.startDay}|${current.period.endDay}';
    if (key == _boundKey) return;
    _boundKey = key;
    _expenseRange?.cancel();
    _incomeRange?.cancel();
    _expenseRange = null;
    _incomeRange = null;
    periodExpenses = const [];
    periodIncomes = const [];
    _stats = const MonthStats(monthKey: '');

    if (current == null) {
      _expensesLoaded = true;
      _incomesLoaded = true;
      return;
    }
    _expensesLoaded = false;
    _incomesLoaded = false;
    final period = current.period;
    _expenseRange = data.expenses.watchRange(period.start, period.endExclusive).listen(
      (value) {
        periodExpenses = value;
        _stats = PeriodStats.fromExpenses(current.id, value);
        _expensesLoaded = true;
        _notify();
      },
      onError: (Object e) {
        error = e;
        _expensesLoaded = true;
        _notify();
      },
    );
    _incomeRange = data.incomes.watchRange(period.start, period.endExclusive).listen(
      (value) {
        periodIncomes = value;
        _incomesLoaded = true;
        _notify();
      },
      onError: (Object e) {
        error = e;
        _incomesLoaded = true;
        _notify();
      },
    );
  }

  // ---- Derived values ------------------------------------------------------

  String get symbol => profile?.currencySymbol ?? 'Rs.';

  /// Totals of the shown budget's period.
  MonthStats get stats => _stats;

  /// Income received during the shown budget's period.
  int get periodIncome => periodIncomes.fold<int>(0, (sum, i) => sum + i.amount);

  /// The user's money right now, or null until they set an opening balance.
  BalanceSummary? get balance => BalanceCalculator.compute(
        profile: profile,
        stats: allStats,
        debts: debts,
      );

  /// Latest expenses and income together, newest first.
  List<ActivityItem> get recentActivity =>
      ActivityItem.merge(recentExpenses, recentIncomes, limit: 8);

  /// Bills, expected income and debts with due dates, soonest first.
  List<DueItem> get dues => Dues.build(
        recurring: recurring,
        debts: debts,
        today: DateTime.now(),
      );

  /// Expenses dated today, newest first (inside the shown period).
  List<Expense> get todayExpenses {
    final today = DateKeys.ofDay(DateTime.now());
    return periodExpenses.where((e) => e.dayKey == today).toList();
  }

  /// Today's spending in everyday categories.
  int get flexibleSpentToday => todayExpenses
      .where((e) => e.categoryKind == CategoryKind.flexible)
      .fold<int>(0, (sum, e) => sum + e.amount);

  /// Today's numbers, or null while there is no budget covering today.
  DailyBudget? get daily {
    final current = budget;
    if (current == null) return null;
    return BudgetCalculator.dailyBudget(
      budget: current,
      stats: _stats,
      spentToday: flexibleSpentToday,
      now: DateTime.now(),
    );
  }

  /// Every budget line with its spending and flag.
  List<CategoryRow> get rows {
    final current = budget;
    if (current == null) return const [];
    final now = DateTime.now();
    final period = current.period;
    return [
      for (final line in current.categories)
        CategoryRow(
          line: line,
          spent: _stats.spentIn(line.categoryId),
          flag: BudgetCalculator.flagFor(
            line: line,
            spent: _stats.spentIn(line.categoryId),
            now: now,
            period: period,
          ),
        ),
    ];
  }

  List<CategoryRow> rowsOfKind(CategoryKind kind) =>
      rows.where((row) => row.line.kind == kind).toList();

  List<CategoryRow> get redFlags =>
      rows.where((row) => row.flag == FlagType.red).toList();

  List<CategoryRow> get greenFlags =>
      rows.where((row) => row.flag == FlagType.green).toList();

  /// Spending in categories that are not part of the shown budget.
  int get unbudgetedSpent {
    final current = budget;
    if (current == null) return 0;
    return BudgetCalculator.unbudgetedSpent(current, _stats);
  }

  Map<String, ExpenseCategory> get categoryById => {
        for (final category in categories) category.id: category,
      };

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _expenseRange?.cancel();
    _incomeRange?.cancel();
    super.dispose();
  }
}
