import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/month_stats.dart';
import '../models/month_summary.dart' show FlagType;
import '../models/monthly_budget.dart';
import '../models/user_profile.dart';
import 'budget_calculator.dart';

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

/// Holds everything the dashboard shows for one month and keeps it live by
/// listening to Firestore. Widgets listen to this object and rebuild when
/// anything changes.
class DashboardController extends ChangeNotifier {
  DashboardController(this.data, this.monthKey) {
    _listen<UserProfile?>('profile', data.profile.watchProfile(), (value) => profile = value);
    _listen<List<ExpenseCategory>>('categories', data.categories.watchCategories(), (value) => categories = value);
    _listen<MonthlyBudget?>('budget', data.budgets.watchBudget(monthKey), (value) => budget = value);
    _listen<MonthStats>('stats', data.expenses.watchStats(monthKey), (value) => stats = value);
    _listen<List<Expense>>('expenses', data.expenses.watchMonth(monthKey), (value) => expenses = value);
  }

  static const int _streamCount = 5;

  final UserData data;
  final String monthKey;

  UserProfile? profile;
  MonthlyBudget? budget;
  MonthStats stats = const MonthStats(monthKey: '');
  List<Expense> expenses = const [];
  List<ExpenseCategory> categories = const [];

  /// The last error from any of the streams (for example missing security
  /// rules), or null.
  Object? error;

  final Set<String> _loaded = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// True until every stream has delivered its first value.
  bool get loading => _loaded.length < _streamCount;

  void _listen<T>(String name, Stream<T> stream, void Function(T value) apply) {
    _subscriptions.add(stream.listen(
      (value) {
        apply(value);
        _loaded.add(name);
        notifyListeners();
      },
      onError: (Object e) {
        error = e;
        _loaded.add(name);
        notifyListeners();
      },
    ));
  }

  // ---- Derived values ------------------------------------------------------

  String get symbol => profile?.currencySymbol ?? 'Rs.';

  /// Expenses dated today, newest first.
  List<Expense> get todayExpenses {
    final today = DateKeys.ofDay(DateTime.now());
    return expenses.where((e) => e.dayKey == today).toList();
  }

  /// Today's spending in everyday categories.
  int get flexibleSpentToday => todayExpenses
      .where((e) => e.categoryKind == CategoryKind.flexible)
      .fold<int>(0, (sum, e) => sum + e.amount);

  /// Today's numbers, or null while no budget has been set for the month.
  DailyBudget? get daily {
    final current = budget;
    if (current == null) return null;
    return BudgetCalculator.dailyBudget(
      budget: current,
      stats: stats,
      spentToday: flexibleSpentToday,
      now: DateTime.now(),
    );
  }

  /// Every budget line with its spending and flag.
  List<CategoryRow> get rows {
    final current = budget;
    if (current == null) return const [];
    final now = DateTime.now();
    return [
      for (final line in current.categories)
        CategoryRow(
          line: line,
          spent: stats.spentIn(line.categoryId),
          flag: BudgetCalculator.flagFor(
            line: line,
            spent: stats.spentIn(line.categoryId),
            now: now,
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

  /// Spending in categories that are not part of this month's budget.
  int get unbudgetedSpent {
    final current = budget;
    if (current == null) return 0;
    return BudgetCalculator.unbudgetedSpent(current, stats);
  }

  Map<String, ExpenseCategory> get categoryById => {
        for (final category in categories) category.id: category,
      };

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
