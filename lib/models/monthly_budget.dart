import 'budget_period.dart';
import 'category.dart';
import 'date_keys.dart';
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

/// A budget: the money the user sets aside for a period, split into category
/// limits. The period can be a week, a month, a year or any dates the user
/// picks. (The class keeps its old name because the first version only had
/// monthly budgets; old documents still read as calendar-month budgets.)
///
/// Stored at users/{uid}/budgets/{id}. A budget that is exactly one calendar
/// month uses its month key ("2026-11") as the id, which is what the monthly
/// report reads; any other budget gets a generated id.
class MonthlyBudget {
  const MonthlyBudget({
    required this.monthKey,
    required this.income,
    this.categories = const [],
    this.updatedAt,
    String? id,
    this.title = '',
    this.periodType = PeriodType.monthly,
    this.startDay,
    this.endDay,
  }) : _id = id;

  final String? _id;

  /// The month the budget starts in, e.g. "2026-11".
  final String monthKey;

  /// The money to budget for the period, in minor units. (Called income
  /// because the first version budgeted a month's income.)
  final int income;
  final List<CategoryBudget> categories;
  final DateTime? updatedAt;

  /// Optional name, e.g. "Eid week".
  final String title;
  final PeriodType periodType;

  /// First and last day as "yyyy-MM-dd". Missing in old documents, which then
  /// cover the whole month of [monthKey].
  final String? startDay;
  final String? endDay;

  /// The document id.
  String get id => _id ?? monthKey;

  DateTime get startDate => DateKeys.parseDay(startDay) ?? DateKeys.startOfMonth(monthKey);

  DateTime get endDate =>
      DateKeys.parseDay(endDay) ?? DateKeys.addDays(DateKeys.endOfMonthExclusive(monthKey), -1);

  BudgetPeriod get period => BudgetPeriod(type: periodType, start: startDate, end: endDate);

  /// The money to budget (same as [income]).
  int get amount => income;

  int _sumOf(CategoryKind kind) => categories
      .where((c) => c.kind == kind)
      .fold<int>(0, (total, c) => total + c.limit);

  /// Money set aside for rent, bills and other fixed costs.
  int get totalFixed => _sumOf(CategoryKind.fixed);

  /// The amount the user wants to save in this period.
  int get savingsGoal => _sumOf(CategoryKind.savings);

  /// Sum of the limits of everyday categories.
  int get flexibleLimits => _sumOf(CategoryKind.flexible);

  /// What is left for everyday spending: amount - fixed - savings.
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

  factory MonthlyBudget.fromMap(String id, Map<String, dynamic> map) {
    return MonthlyBudget(
      id: id,
      monthKey: readString(map, 'monthKey', id),
      income: readInt(map, 'income'),
      categories: readMapList(map, 'categories').map(CategoryBudget.fromMap).toList(),
      updatedAt: readDate(map, 'updatedAt'),
      title: readString(map, 'title'),
      periodType: enumByName(PeriodType.values, map['periodType'], PeriodType.monthly),
      startDay: readStringOrNull(map, 'startDay'),
      endDay: readStringOrNull(map, 'endDay'),
    );
  }

  Map<String, dynamic> toMap() => {
        'monthKey': monthKey,
        'income': income,
        'categories': categories.map((c) => c.toMap()).toList(),
        'title': title,
        'periodType': periodType.name,
        'startDay': DateKeys.ofDay(startDate),
        'endDay': DateKeys.ofDay(endDate),
      };

  /// A copy with some fields changed. Giving a new [monthKey] moves the
  /// budget to that calendar month (new id, dates and period reset).
  MonthlyBudget copyWith({
    int? income,
    List<CategoryBudget>? categories,
    String? monthKey,
    String? title,
    PeriodType? periodType,
    String? startDay,
    String? endDay,
  }) {
    final moved = monthKey != null && monthKey != this.monthKey;
    return MonthlyBudget(
      id: moved ? monthKey : _id,
      monthKey: monthKey ?? this.monthKey,
      income: income ?? this.income,
      categories: categories ?? this.categories,
      updatedAt: updatedAt,
      title: title ?? this.title,
      periodType: moved ? PeriodType.monthly : (periodType ?? this.periodType),
      startDay: moved ? null : (startDay ?? this.startDay),
      endDay: moved ? null : (endDay ?? this.endDay),
    );
  }
}
