import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'date_keys.dart';
import 'map_readers.dart';

/// Suggested labels for where money came from. The user can type any other.
const List<String> incomeSources = [
  'Salary',
  'Business',
  'Freelance',
  'Gift',
  'Refund',
  'Other',
];

/// Money received. Stored at users/{uid}/incomes/{id}.
class Income {
  const Income({
    this.id = '',
    required this.amount,
    required this.source,
    this.note = '',
    required this.date,
    this.recurringId,
    this.createdAt,
    this.updatedAt,
  });

  /// Empty for an income that has not been saved yet.
  final String id;

  /// Positive amount in minor units.
  final int amount;

  /// Where it came from, e.g. "Salary".
  final String source;
  final String note;

  /// When the money arrived, in local time (can be backdated).
  final DateTime date;

  /// The recurring income (a standing salary, say) this was recorded from.
  final String? recurringId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get monthKey => DateKeys.ofMonth(date);
  String get dayKey => DateKeys.ofDay(date);

  factory Income.fromMap(String id, Map<String, dynamic> map) {
    return Income(
      id: id,
      amount: readInt(map, 'amount'),
      source: readString(map, 'source', 'Other'),
      note: readString(map, 'note'),
      date: readDate(map, 'date') ?? DateTime.fromMillisecondsSinceEpoch(0),
      recurringId: readStringOrNull(map, 'recurringId'),
      createdAt: readDate(map, 'createdAt'),
      updatedAt: readDate(map, 'updatedAt'),
    );
  }

  /// Fields written to Firestore. createdAt and updatedAt are added by the
  /// repository as server timestamps.
  Map<String, dynamic> toMap() => {
        'amount': amount,
        'source': source,
        'note': note,
        'date': Timestamp.fromDate(date),
        'dayKey': dayKey,
        'monthKey': monthKey,
        if (recurringId != null) 'recurringId': recurringId,
      };

  Income copyWith({int? amount, String? source, String? note, DateTime? date}) {
    return Income(
      id: id,
      amount: amount ?? this.amount,
      source: source ?? this.source,
      note: note ?? this.note,
      date: date ?? this.date,
      recurringId: recurringId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
