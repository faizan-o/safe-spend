import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/budget_period.dart';
import '../models/date_keys.dart';
import '../models/monthly_budget.dart';

/// Reads and writes users/{uid}/budgets.
///
/// A budget covers any period (a week, a month, a year or custom dates). A
/// budget that is exactly one calendar month uses the month key ("2026-11")
/// as its document id, which is what the monthly report reads; every other
/// budget gets a generated id.
class BudgetRepository {
  BudgetRepository(this._collection);

  final CollectionReference<Map<String, dynamic>> _collection;

  /// Live budget with this id (the month key for monthly budgets), or null.
  Stream<MonthlyBudget?> watchBudget(String id) {
    return _collection.doc(id).snapshots().map((snapshot) => _parse(snapshot));
  }

  Future<MonthlyBudget?> getBudget(String id) async {
    return _parse(await _collection.doc(id).get());
  }

  /// Every budget, newest period first. There are only ever a few, so they
  /// are all loaded and sorted here rather than by the database (which would
  /// skip documents saved before budgets had dates).
  Stream<List<MonthlyBudget>> watchBudgets() {
    return _collection.snapshots().map((snapshot) => sorted([
          for (final doc in snapshot.docs) MonthlyBudget.fromMap(doc.id, doc.data()),
        ]));
  }

  Future<List<MonthlyBudget>> getBudgets() async {
    final snapshot = await _collection.get();
    return sorted([
      for (final doc in snapshot.docs) MonthlyBudget.fromMap(doc.id, doc.data()),
    ]);
  }

  /// Newest period first (latest start day, then latest end day).
  static List<MonthlyBudget> sorted(List<MonthlyBudget> budgets) {
    budgets.sort((a, b) {
      final byStart = b.startDate.compareTo(a.startDate);
      return byStart != 0 ? byStart : b.endDate.compareTo(a.endDate);
    });
    return budgets;
  }

  /// A new document id for a budget over [period]: the month key when the
  /// period is one calendar month, otherwise a generated id.
  String newIdFor(BudgetPeriod period) {
    return period.isCalendarMonth ? DateKeys.ofMonth(period.start) : _collection.doc().id;
  }

  /// Creates or replaces the budget with [MonthlyBudget.id].
  Future<void> saveBudget(MonthlyBudget budget) {
    return _collection.doc(budget.id).set(
      {...budget.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Starts the next budget from the most recent one: same amount and
  /// category limits, on the period that follows it (moved on until it
  /// reaches [today]). Returns the new budget, or null when there is no
  /// earlier budget to repeat.
  Future<MonthlyBudget?> repeatLatest({DateTime? today}) async {
    final day = DateKeys.startOfDay(today ?? DateTime.now());
    final budgets = await getBudgets();
    if (budgets.isEmpty) return null;
    // The budget that ends last is the one to continue.
    final latest = budgets.reduce((a, b) => a.endDate.isAfter(b.endDate) ? a : b);
    final period = latest.period.advancedTo(day);
    final repeated = latest.period.startDay == period.startDay ? latest.period.following() : period;

    final budget = MonthlyBudget(
      id: newIdFor(repeated),
      monthKey: DateKeys.ofMonth(repeated.start),
      income: latest.income,
      categories: latest.categories,
      title: latest.title,
      periodType: repeated.type,
      startDay: repeated.startDay,
      endDay: repeated.endDay,
    );
    // Do not overwrite a budget that already has this calendar-month id.
    if (await getBudget(budget.id) != null) return null;
    await saveBudget(budget);
    return budget;
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

  Future<void> deleteBudget(String id) => _collection.doc(id).delete();

  MonthlyBudget? _parse(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return null;
    return MonthlyBudget.fromMap(snapshot.id, data);
  }
}
