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
      updatedAt: readDate(map, 'updatedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'monthKey': monthKey,
        'totalSpent': totalSpent,
        'flexibleSpent': flexibleSpent,
        'expenseCount': expenseCount,
        'spentByCategory': spentByCategory,
        'spentByDay': spentByDay,
      };
}
