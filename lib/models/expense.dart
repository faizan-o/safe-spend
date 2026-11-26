import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'category.dart';
import 'date_keys.dart';
import 'map_readers.dart';

/// How an expense was entered.
enum ExpenseSource { manual, voice }

/// A single expense. Stored at users/{uid}/expenses/{id}.
class Expense {
  const Expense({
    this.id = '',
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    required this.categoryKind,
    this.note = '',
    required this.date,
    this.source = ExpenseSource.manual,
    this.transcript,
    this.createdAt,
    this.updatedAt,
  });

  /// Empty for an expense that has not been saved yet.
  final String id;

  /// Positive amount in minor units.
  final int amount;
  final String categoryId;

  /// Name and kind are copied from the category when the expense is saved so
  /// lists and summaries need no second lookup.
  final String categoryName;
  final CategoryKind categoryKind;
  final String note;

  /// When the money was spent (can be backdated), in local time.
  final DateTime date;
  final ExpenseSource source;

  /// What the user said, when [source] is voice. Kept so a wrong parse can be
  /// corrected or reviewed.
  final String? transcript;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get monthKey => DateKeys.ofMonth(date);
  String get dayKey => DateKeys.ofDay(date);

  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    return Expense(
      id: id,
      amount: readInt(map, 'amount'),
      categoryId: readString(map, 'categoryId'),
      categoryName: readString(map, 'categoryName'),
      categoryKind: enumByName(CategoryKind.values, map['categoryKind'], CategoryKind.flexible),
      note: readString(map, 'note'),
      date: readDate(map, 'date') ?? DateTime.fromMillisecondsSinceEpoch(0),
      source: enumByName(ExpenseSource.values, map['source'], ExpenseSource.manual),
      transcript: readStringOrNull(map, 'transcript'),
      createdAt: readDate(map, 'createdAt'),
      updatedAt: readDate(map, 'updatedAt'),
    );
  }

  /// Fields written to Firestore. createdAt and updatedAt are added by the
  /// repository as server timestamps. dayKey and monthKey are stored so the
  /// data can be grouped without parsing dates.
  Map<String, dynamic> toMap() => {
        'amount': amount,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'categoryKind': categoryKind.name,
        'note': note,
        'date': Timestamp.fromDate(date),
        'dayKey': dayKey,
        'monthKey': monthKey,
        'source': source.name,
        'transcript': transcript,
      };

  Expense copyWith({
    int? amount,
    ExpenseCategory? category,
    String? note,
    DateTime? date,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      categoryId: category?.id ?? categoryId,
      categoryName: category?.name ?? categoryName,
      categoryKind: category?.kind ?? categoryKind,
      note: note ?? this.note,
      date: date ?? this.date,
      source: source,
      transcript: transcript,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
