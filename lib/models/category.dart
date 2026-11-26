import 'map_readers.dart';

/// How a category behaves in the daily budget:
/// - [fixed]: bills that are set aside up front (rent, utilities, committee).
/// - [flexible]: everyday spending. Only this money feeds the daily number.
/// - [savings]: the amount the user wants to keep.
enum CategoryKind { fixed, flexible, savings }

/// A spending category the user can pick when logging an expense.
/// Stored at users/{uid}/categories/{id}.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    this.kind = CategoryKind.flexible,
    this.sortOrder = 0,
    this.archived = false,
  });

  final String id;
  final String name;

  /// Name of a Material icon, mapped to an IconData by the UI.
  final String iconKey;

  /// ARGB color, e.g. 0xFF2E7D32.
  final int colorValue;
  final CategoryKind kind;
  final int sortOrder;

  /// Categories are archived instead of deleted so old expenses and
  /// summaries that mention them stay valid.
  final bool archived;

  factory ExpenseCategory.fromMap(String id, Map<String, dynamic> map) {
    return ExpenseCategory(
      id: id,
      name: readString(map, 'name'),
      iconKey: readString(map, 'iconKey', 'category'),
      colorValue: readInt(map, 'colorValue', 0xFF546E7A),
      kind: enumByName(CategoryKind.values, map['kind'], CategoryKind.flexible),
      sortOrder: readInt(map, 'sortOrder'),
      archived: readBool(map, 'archived'),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'iconKey': iconKey,
        'colorValue': colorValue,
        'kind': kind.name,
        'sortOrder': sortOrder,
        'archived': archived,
      };

  ExpenseCategory copyWith({
    String? name,
    String? iconKey,
    int? colorValue,
    CategoryKind? kind,
    int? sortOrder,
    bool? archived,
  }) {
    return ExpenseCategory(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      kind: kind ?? this.kind,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }
}

/// Categories created for every new account. They use fixed ids so the same
/// category has the same id for every user.
const List<ExpenseCategory> defaultCategories = [
  ExpenseCategory(id: 'food', name: 'Food & dining', iconKey: 'restaurant', colorValue: 0xFFEF6C00, sortOrder: 0),
  ExpenseCategory(id: 'groceries', name: 'Groceries', iconKey: 'shopping_basket', colorValue: 0xFF2E7D32, sortOrder: 1),
  ExpenseCategory(id: 'transport', name: 'Transport', iconKey: 'directions_bus', colorValue: 0xFF1565C0, sortOrder: 2),
  ExpenseCategory(id: 'shopping', name: 'Shopping', iconKey: 'shopping_bag', colorValue: 0xFFAD1457, sortOrder: 3),
  ExpenseCategory(id: 'entertainment', name: 'Entertainment', iconKey: 'movie', colorValue: 0xFF6A1B9A, sortOrder: 4),
  ExpenseCategory(id: 'health', name: 'Health', iconKey: 'favorite', colorValue: 0xFFC62828, sortOrder: 5),
  ExpenseCategory(id: 'education', name: 'Education', iconKey: 'school', colorValue: 0xFF00838F, sortOrder: 6),
  ExpenseCategory(id: 'other', name: 'Other', iconKey: 'category', colorValue: 0xFF546E7A, sortOrder: 7),
  ExpenseCategory(id: 'rent', name: 'Rent', iconKey: 'home', colorValue: 0xFF4E342E, kind: CategoryKind.fixed, sortOrder: 8),
  ExpenseCategory(id: 'bills', name: 'Bills & utilities', iconKey: 'receipt_long', colorValue: 0xFF455A64, kind: CategoryKind.fixed, sortOrder: 9),
  ExpenseCategory(id: 'committee', name: 'Committee (kameti)', iconKey: 'groups', colorValue: 0xFF827717, kind: CategoryKind.fixed, sortOrder: 10),
  ExpenseCategory(id: 'savings', name: 'Savings', iconKey: 'savings', colorValue: 0xFF00695C, kind: CategoryKind.savings, sortOrder: 11),
];
