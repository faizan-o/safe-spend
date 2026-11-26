import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/monthly_budget.dart';

/// Reads and writes users/{uid}/budgets. The document id is the month key
/// (for example "2026-11"), so each month has exactly one budget.
class BudgetRepository {
  BudgetRepository(this._collection);

  final CollectionReference<Map<String, dynamic>> _collection;

  /// Live budget for a month, or null when none has been set yet.
  Stream<MonthlyBudget?> watchBudget(String monthKey) {
    return _collection.doc(monthKey).snapshots().map((snapshot) => _parse(snapshot));
  }

  Future<MonthlyBudget?> getBudget(String monthKey) async {
    return _parse(await _collection.doc(monthKey).get());
  }

  /// Creates or replaces the budget for [MonthlyBudget.monthKey].
  Future<void> saveBudget(MonthlyBudget budget) {
    return _collection.doc(budget.monthKey).set(
      {...budget.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Starts a new month from an earlier one ("same as last month").
  /// Returns the copied budget, or null when the source month has none.
  Future<MonthlyBudget?> copyFromMonth({
    required String fromMonthKey,
    required String toMonthKey,
  }) async {
    final source = await getBudget(fromMonthKey);
    if (source == null) return null;
    final copy = source.copyWith(monthKey: toMonthKey);
    await saveBudget(copy);
    return copy;
  }

  Future<void> deleteBudget(String monthKey) => _collection.doc(monthKey).delete();

  MonthlyBudget? _parse(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return null;
    return MonthlyBudget.fromMap(snapshot.id, data);
  }
}
