import '../models/expense.dart';
import '../models/income.dart';

/// One line in a mixed list of expenses and income.
class ActivityItem {
  const ActivityItem.expense(Expense this.expense) : income = null;
  const ActivityItem.income(Income this.income) : expense = null;

  final Expense? expense;
  final Income? income;

  DateTime get date => expense?.date ?? income!.date;
  bool get isIncome => income != null;
  String get id => expense?.id ?? income!.id;

  /// Signed amount for totals: income is positive, expenses negative.
  int get signedAmount => isIncome ? income!.amount : -expense!.amount;

  /// Expenses and incomes merged, newest first. [limit] keeps only the newest.
  static List<ActivityItem> merge(
    Iterable<Expense> expenses,
    Iterable<Income> incomes, {
    int? limit,
  }) {
    final items = <ActivityItem>[
      for (final e in expenses) ActivityItem.expense(e),
      for (final i in incomes) ActivityItem.income(i),
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (limit != null && items.length > limit) return items.sublist(0, limit);
    return items;
  }
}
