import 'map_readers.dart';

/// Whether a category is overspending (red), saving (green) or on track.
enum FlagType { red, green, none }

/// How one category did over the month.
class CategoryResult {
  const CategoryResult({
    required this.categoryId,
    required this.name,
    required this.limit,
    required this.spent,
    this.flag = FlagType.none,
  });

  final String categoryId;
  final String name;
  final int limit;
  final int spent;
  final FlagType flag;

  /// Share of the limit that was used (1.0 = exactly on budget).
  double get usedRatio => limit > 0 ? spent / limit : 0;

  factory CategoryResult.fromMap(Map<String, dynamic> map) {
    return CategoryResult(
      categoryId: readString(map, 'categoryId'),
      name: readString(map, 'name'),
      limit: readInt(map, 'limit'),
      spent: readInt(map, 'spent'),
      flag: enumByName(FlagType.values, map['flag'], FlagType.none),
    );
  }

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'name': name,
        'limit': limit,
        'spent': spent,
        'flag': flag.name,
      };
}

/// The generated report for a finished month.
/// Stored at users/{uid}/monthSummaries/{monthKey}.
class MonthSummary {
  const MonthSummary({
    required this.monthKey,
    required this.income,
    required this.totalSpent,
    required this.flexibleSpent,
    required this.saved,
    this.categories = const [],
    this.suggestion = '',
    this.generatedAt,
  });

  final String monthKey;
  final int income;
  final int totalSpent;
  final int flexibleSpent;

  /// Money left unspent from the flexible pool (can be negative).
  final int saved;
  final List<CategoryResult> categories;

  /// One suggestion for next month.
  final String suggestion;
  final DateTime? generatedAt;

  List<CategoryResult> get redFlags =>
      categories.where((c) => c.flag == FlagType.red).toList();

  List<CategoryResult> get greenFlags =>
      categories.where((c) => c.flag == FlagType.green).toList();

  factory MonthSummary.fromMap(String monthKey, Map<String, dynamic> map) {
    return MonthSummary(
      monthKey: monthKey,
      income: readInt(map, 'income'),
      totalSpent: readInt(map, 'totalSpent'),
      flexibleSpent: readInt(map, 'flexibleSpent'),
      saved: readInt(map, 'saved'),
      categories: readMapList(map, 'categories').map(CategoryResult.fromMap).toList(),
      suggestion: readString(map, 'suggestion'),
      generatedAt: readDate(map, 'generatedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'monthKey': monthKey,
        'income': income,
        'totalSpent': totalSpent,
        'flexibleSpent': flexibleSpent,
        'saved': saved,
        'categories': categories.map((c) => c.toMap()).toList(),
        'suggestion': suggestion,
      };
}
