import 'category.dart';
import 'map_readers.dart';

/// One category's limit inside a monthly budget.
///
/// The category's name, icon and color are copied in (a snapshot), so a month's
/// budget still reads correctly after the category is renamed or archived.
class CategoryBudget {
  const CategoryBudget({
    required this.categoryId,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.kind,
    required this.limit,
  });

  final String categoryId;
  final String name;
  final String iconKey;
  final int colorValue;
  final CategoryKind kind;

  /// Budget for the month, in minor units.
  final int limit;

  factory CategoryBudget.fromCategory(ExpenseCategory category, int limit) {
    return CategoryBudget(
      categoryId: category.id,
      name: category.name,
      iconKey: category.iconKey,
      colorValue: category.colorValue,
      kind: category.kind,
      limit: limit,
    );
  }

  factory CategoryBudget.fromMap(Map<String, dynamic> map) {
    return CategoryBudget(
      categoryId: readString(map, 'categoryId'),
      name: readString(map, 'name'),
      iconKey: readString(map, 'iconKey', 'category'),
      colorValue: readInt(map, 'colorValue', 0xFF546E7A),
      kind: enumByName(CategoryKind.values, map['kind'], CategoryKind.flexible),
      limit: readInt(map, 'limit'),
    );
  }

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'name': name,
        'iconKey': iconKey,
        'colorValue': colorValue,
        'kind': kind.name,
        'limit': limit,
      };

  CategoryBudget copyWith({int? limit}) {
    return CategoryBudget(
      categoryId: categoryId,
      name: name,
      iconKey: iconKey,
      colorValue: colorValue,
      kind: kind,
      limit: limit ?? this.limit,
    );
  }
}

/// The budget the user declares at the start of a month.
/// Stored at users/{uid}/budgets/{monthKey}, for example budgets/2026-11.
class MonthlyBudget {
  const MonthlyBudget({
    required this.monthKey,
    required this.income,
    this.categories = const [],
    this.updatedAt,
  });

  final String monthKey;

  /// Income for the month, in minor units.
  final int income;
  final List<CategoryBudget> categories;
  final DateTime? updatedAt;

  int _sumOf(CategoryKind kind) => categories
      .where((c) => c.kind == kind)
      .fold<int>(0, (total, c) => total + c.limit);

  /// Money set aside for rent, bills and other fixed costs.
  int get totalFixed => _sumOf(CategoryKind.fixed);

  /// The amount the user wants to save this month.
  int get savingsGoal => _sumOf(CategoryKind.savings);

  /// Sum of the limits of everyday categories.
  int get flexibleLimits => _sumOf(CategoryKind.flexible);

  /// What is left for everyday spending: income - fixed - savings.
  /// This is the pool the daily safe-to-spend number is taken from.
  int get flexiblePool => income - totalFixed - savingsGoal;

  /// Flexible money not yet given to any category (negative = over-allocated).
  int get unallocated => flexiblePool - flexibleLimits;

  CategoryBudget? forCategory(String categoryId) {
    for (final c in categories) {
      if (c.categoryId == categoryId) return c;
    }
    return null;
  }

  factory MonthlyBudget.fromMap(String monthKey, Map<String, dynamic> map) {
    return MonthlyBudget(
      monthKey: monthKey,
      income: readInt(map, 'income'),
      categories: readMapList(map, 'categories').map(CategoryBudget.fromMap).toList(),
      updatedAt: readDate(map, 'updatedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'monthKey': monthKey,
        'income': income,
        'categories': categories.map((c) => c.toMap()).toList(),
      };

  MonthlyBudget copyWith({
    int? income,
    List<CategoryBudget>? categories,
    String? monthKey,
  }) {
    return MonthlyBudget(
      monthKey: monthKey ?? this.monthKey,
      income: income ?? this.income,
      categories: categories ?? this.categories,
    );
  }
}
