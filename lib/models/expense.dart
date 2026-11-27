import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'category.dart';
import 'date_keys.dart';
import 'map_readers.dart';

/// How an expense was entered.
enum ExpenseSource { manual, voice, receipt }

/// One line of a receipt. Only receipts read by the n8n workflow have these.
class ExpenseItem {
  const ExpenseItem({required this.description, required this.amount, this.quantity = 1});

  final String description;

  /// Line total in minor units.
  final int amount;
  final int quantity;

  factory ExpenseItem.fromMap(Map<String, dynamic> map) => ExpenseItem(
        description: readString(map, 'description'),
        amount: readInt(map, 'amount'),
        quantity: readInt(map, 'quantity', 1),
      );

  Map<String, dynamic> toMap() => {
        'description': description,
        'amount': amount,
        'quantity': quantity,
      };
}

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
    this.merchant,
    this.confidence,
    this.requestId,
    this.receiptId,
    this.items = const [],
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

  /// Shop or payee, read from a receipt or from what was said.
  final String? merchant;

  /// How sure the n8n workflow was (0 to 1). Null for manual expenses.
  final double? confidence;

  /// The client request id the n8n workflow saved this under. The expense id
  /// is derived from it, so a repeated delivery cannot create a duplicate.
  final String? requestId;

  /// The receipt (users/{uid}/receipts/{receiptId}) this expense came from.
  final String? receiptId;

  /// Line items, for receipts.
  final List<ExpenseItem> items;
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
      merchant: readStringOrNull(map, 'merchant'),
      confidence: map['confidence'] is num ? (map['confidence'] as num).toDouble() : null,
      requestId: readStringOrNull(map, 'requestId'),
      receiptId: readStringOrNull(map, 'receiptId'),
      items: readMapList(map, 'items').map(ExpenseItem.fromMap).toList(),
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
        if (merchant != null) 'merchant': merchant,
        if (confidence != null) 'confidence': confidence,
        if (requestId != null) 'requestId': requestId,
        if (receiptId != null) 'receiptId': receiptId,
        if (items.isNotEmpty) 'items': items.map((i) => i.toMap()).toList(),
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
      merchant: merchant,
      confidence: confidence,
      requestId: requestId,
      receiptId: receiptId,
      items: items,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
