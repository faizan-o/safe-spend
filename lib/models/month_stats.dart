import 'map_readers.dart';

/// Running totals for one month, kept up to date whenever an expense is added,
/// edited or deleted. Stored at users/{uid}/monthStats/{monthKey}.
///
/// Reading this single small document gives the home screen its numbers
/// without downloading every expense of the month.
class MonthStats {
  const MonthStats({
    required this.monthKey,
    this.totalSpent = 0,
    this.flexibleSpent = 0,
    this.expenseCount = 0,
    this.spentByCategory = const {},
    this.spentByDay = const {},
    this.totalIncome = 0,
    this.incomeCount = 0,
    this.incomeByDay = const {},
    this.updatedAt,
  });

  final String monthKey;

  /// Everything spent this month, in minor units.
  final int totalSpent;

  /// Spent in flexible categories only. The daily safe-to-spend number is
  /// worked out from this, not from [totalSpent].
  final int flexibleSpent;
  final int expenseCount;

  /// categoryId -> amount spent.
  final Map<String, int> spentByCategory;

  /// Two-digit day of month ("05") -> amount spent that day.
  final Map<String, int> spentByDay;

  /// Money received this month (salary, gifts, refunds...), in minor units.
  final int totalIncome;
  final int incomeCount;

  /// Two-digit day of month ("05") -> income received that day.
  final Map<String, int> incomeByDay;
  final DateTime? updatedAt;

  int spentIn(String categoryId) => spentByCategory[categoryId] ?? 0;

  int spentOnDay(DateTime date) =>
      spentByDay[date.day.toString().padLeft(2, '0')] ?? 0;

  factory MonthStats.empty(String monthKey) => MonthStats(monthKey: monthKey);

  factory MonthStats.fromMap(String monthKey, Map<String, dynamic> map) {
    return MonthStats(
      monthKey: monthKey,
      totalSpent: readInt(map, 'totalSpent'),
      flexibleSpent: readInt(map, 'flexibleSpent'),
      expenseCount: readInt(map, 'expenseCount'),
      spentByCategory: readIntMap(map, 'spentByCategory'),
      spentByDay: readIntMap(map, 'spentByDay'),
      totalIncome: readInt(map, 'totalIncome'),
      incomeCount: readInt(map, 'incomeCount'),
      incomeByDay: readIntMap(map, 'incomeByDay'),
      updatedAt: readDate(map, 'updatedAt'),
    );
  }

  /// The spending fields. Written when the totals are rebuilt from expenses.
  Map<String, dynamic> toExpenseMap() => {
        'monthKey': monthKey,
        'totalSpent': totalSpent,
        'flexibleSpent': flexibleSpent,
        'expenseCount': expenseCount,
        'spentByCategory': spentByCategory,
        'spentByDay': spentByDay,
      };

  /// The income fields. Written when the totals are rebuilt from incomes.
  Map<String, dynamic> toIncomeMap() => {
        'monthKey': monthKey,
        'totalIncome': totalIncome,
        'incomeCount': incomeCount,
        'incomeByDay': incomeByDay,
      };

  Map<String, dynamic> toMap() => {...toExpenseMap(), ...toIncomeMap()};

  /// Spending on the days of the month from [fromDay] on (1-based). Used for
  /// the month an opening balance was set in.
  int spentFromDay(int fromDay) => _sumFrom(spentByDay, fromDay);

  int incomeFromDay(int fromDay) => _sumFrom(incomeByDay, fromDay);

  static int _sumFrom(Map<String, int> byDay, int fromDay) {
    var total = 0;
    byDay.forEach((day, amount) {
      final number = int.tryParse(day);
      if (number != null && number >= fromDay) total += amount;
    });
    return total;
  }
}
