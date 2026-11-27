import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/month_stats.dart';

/// Totals for any list of expenses (a week, a year, custom dates), in the same
/// shape as the stored month totals so the dashboard widgets can use either.
class PeriodStats {
  const PeriodStats._();

  /// [key] only labels the result (the budget id, for example).
  static MonthStats fromExpenses(String key, Iterable<Expense> expenses) {
    var total = 0;
    var flexible = 0;
    var count = 0;
    final byCategory = <String, int>{};
    final byDay = <String, int>{};
    for (final expense in expenses) {
      total += expense.amount;
      if (expense.categoryKind == CategoryKind.flexible) flexible += expense.amount;
      count++;
      byCategory[expense.categoryId] = (byCategory[expense.categoryId] ?? 0) + expense.amount;
      final day = DateKeys.dayOfMonth(expense.date);
      byDay[day] = (byDay[day] ?? 0) + expense.amount;
    }
    return MonthStats(
      monthKey: key,
      totalSpent: total,
      flexibleSpent: flexible,
      expenseCount: count,
      spentByCategory: byCategory,
      spentByDay: byDay,
    );
  }
}
