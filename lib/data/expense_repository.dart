import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/month_stats.dart';

/// Reads and writes users/{uid}/expenses and keeps users/{uid}/monthStats in
/// step with them.
///
/// Every add, edit and delete writes the expense and the month's running
/// totals in one atomic batch, so the totals can never drift from the
/// expenses. Batches work offline: the local view updates immediately and the
/// returned Future completes when the server confirms. Screens should not
/// block on these Futures while the device may be offline.
class ExpenseRepository {
  ExpenseRepository(this._firestore, this._expenses, this._stats);

  final FirebaseFirestore _firestore;
  final CollectionReference<Map<String, dynamic>> _expenses;
  final CollectionReference<Map<String, dynamic>> _stats;

  // ---- Writes ------------------------------------------------------------

  /// Saves a new expense and returns its generated id.
  Future<String> addExpense(Expense expense) async {
    final batch = _firestore.batch();
    final id = queueAdd(batch, expense);
    await batch.commit();
    return id;
  }

  /// Adds a new expense (and its month totals) to [batch] without committing.
  /// Pass [id] to save under a chosen document id, for example so a recurring
  /// payment can never be recorded twice. Returns the id.
  String queueAdd(WriteBatch batch, Expense expense, {String? id}) {
    _checkAmount(expense);
    final ref = id == null ? _expenses.doc() : _expenses.doc(id);
    batch.set(ref, {
      ...expense.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _queueStats(batch, [(expense, 1)]);
    return ref.id;
  }

  /// Whether an expense with this id exists (the device's copy counts, so a
  /// write still waiting to sync is found too).
  Future<bool> exists(String id) async {
    final ref = _expenses.doc(id);
    // The device's own copy first: it includes writes still waiting to sync.
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) return true;
    } catch (_) {}
    // Then the server, but never wait long: offline, an unknown id counts as new.
    try {
      final snapshot = await ref.get().timeout(const Duration(seconds: 4));
      return snapshot.exists;
    } catch (_) {
      return false;
    }
  }

  /// One expense, or null when it does not exist.
  Future<Expense?> getExpense(String id) async {
    final snapshot = await _expenses.doc(id).get();
    final data = snapshot.data();
    return data == null ? null : Expense.fromMap(snapshot.id, data);
  }

  /// Saves an edited expense. [previous] must be the expense as it was before
  /// the edit; it is used to take the old amounts out of the totals.
  Future<void> updateExpense({
    required Expense previous,
    required Expense updated,
  }) async {
    if (previous.id.isEmpty || previous.id != updated.id) {
      throw ArgumentError('previous and updated must be the same saved expense');
    }
    _checkAmount(updated);
    final batch = _firestore.batch()
      ..update(_expenses.doc(updated.id), {
        ...updated.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    _queueStats(batch, [(previous, -1), (updated, 1)]);
    await batch.commit();
  }

  Future<void> deleteExpense(Expense expense) async {
    if (expense.id.isEmpty) throw ArgumentError('expense has not been saved');
    final batch = _firestore.batch()..delete(_expenses.doc(expense.id));
    _queueStats(batch, [(expense, -1)]);
    await batch.commit();
  }

  // ---- Reads -------------------------------------------------------------

  /// Live expenses of a month, newest first.
  Stream<List<Expense>> watchMonth(String monthKey) {
    return _inRange(
      DateKeys.startOfMonth(monthKey),
      DateKeys.endOfMonthExclusive(monthKey),
    ).snapshots().map(_parse);
  }

  /// Live expenses from [start] up to (not including) [endExclusive], newest first.
  Stream<List<Expense>> watchRange(DateTime start, DateTime endExclusive) {
    return _inRange(start, endExclusive).snapshots().map(_parse);
  }

  /// Live expenses of one day, newest first.
  Stream<List<Expense>> watchDay(DateTime day) {
    final start = DateKeys.startOfDay(day);
    return _inRange(start, DateTime(start.year, start.month, start.day + 1))
        .snapshots()
        .map(_parse);
  }

  /// The latest expenses across all months.
  Stream<List<Expense>> watchRecent({int limit = 20}) {
    return _expenses
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map(_parse);
  }

  /// Expenses of one category in a month. Needs the composite index in
  /// firestore.indexes.json (categoryId, date).
  Stream<List<Expense>> watchCategoryInMonth(String categoryId, String monthKey) {
    return _expenses
        .where('categoryId', isEqualTo: categoryId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateKeys.startOfMonth(monthKey)))
        .where('date', isLessThan: Timestamp.fromDate(DateKeys.endOfMonthExclusive(monthKey)))
        .orderBy('date', descending: true)
        .snapshots()
        .map(_parse);
  }

  /// One-off read of a date range. Use it for the prediction history
  /// (for example the last eight weeks).
  Future<List<Expense>> getRange(DateTime start, DateTime endExclusive) async {
    return _parse(await _inRange(start, endExclusive).get());
  }

  /// Live running totals for a month (all zero when nothing is logged yet).
  Stream<MonthStats> watchStats(String monthKey) {
    return _stats.doc(monthKey).snapshots().map(
          (snapshot) => MonthStats.fromMap(monthKey, snapshot.data() ?? const {}),
        );
  }

  /// Live running totals of every month that has any (a few small documents).
  /// The balance is worked out from these.
  Stream<List<MonthStats>> watchAllStats() {
    return _stats.snapshots().map((snapshot) => [
          for (final doc in snapshot.docs) MonthStats.fromMap(doc.id, doc.data()),
        ]);
  }

  Future<MonthStats> getStats(String monthKey) async {
    final snapshot = await _stats.doc(monthKey).get();
    return MonthStats.fromMap(monthKey, snapshot.data() ?? const {});
  }

  /// Recomputes a month's totals from its expenses. A repair tool: use it if
  /// the totals ever look wrong. Needs the device to be online.
  Future<MonthStats> rebuildStats(String monthKey) async {
    final expenses = await getRange(
      DateKeys.startOfMonth(monthKey),
      DateKeys.endOfMonthExclusive(monthKey),
    );
    final delta = _StatsDelta();
    for (final expense in expenses) {
      delta.add(expense, 1);
    }
    final stats = delta.toStats(monthKey);
    // Only the spending fields are replaced; income totals are left alone.
    await _stats.doc(monthKey).set(
      {
        ...stats.toExpenseMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(mergeFields: [
        'monthKey',
        'totalSpent',
        'flexibleSpent',
        'expenseCount',
        'spentByCategory',
        'spentByDay',
        'updatedAt',
      ]),
    );
    return stats;
  }

  // ---- Internals ---------------------------------------------------------

  Query<Map<String, dynamic>> _inRange(DateTime start, DateTime endExclusive) {
    return _expenses
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(endExclusive))
        .orderBy('date', descending: true);
  }

  List<Expense> _parse(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs
        .map((doc) => Expense.fromMap(doc.id, doc.data()))
        .toList();
  }

  void _checkAmount(Expense expense) {
    if (expense.amount <= 0) {
      throw ArgumentError.value(expense.amount, 'amount', 'must be greater than zero');
    }
    if (expense.categoryId.isEmpty) {
      throw ArgumentError('an expense needs a category');
    }
  }

  /// Adds the month-stats updates for [changes] to [batch]. Each change is an
  /// expense and +1 (added) or -1 (removed). Changes are grouped by month
  /// because an edit can move an expense into another month.
  void _queueStats(WriteBatch batch, List<(Expense, int)> changes) {
    final deltas = <String, _StatsDelta>{};
    for (final (expense, sign) in changes) {
      deltas.putIfAbsent(expense.monthKey, _StatsDelta.new).add(expense, sign);
    }
    for (final entry in deltas.entries) {
      batch.set(
        _stats.doc(entry.key),
        entry.value.toWrite(entry.key),
        SetOptions(merge: true),
      );
    }
  }
}

/// Accumulates how a month's totals change.
class _StatsDelta {
  int total = 0;
  int flexible = 0;
  int count = 0;
  final Map<String, int> byCategory = {};
  final Map<String, int> byDay = {};

  void add(Expense expense, int sign) {
    final amount = expense.amount * sign;
    total += amount;
    if (expense.categoryKind == CategoryKind.flexible) flexible += amount;
    count += sign;
    byCategory[expense.categoryId] = (byCategory[expense.categoryId] ?? 0) + amount;
    final day = DateKeys.dayOfMonth(expense.date);
    byDay[day] = (byDay[day] ?? 0) + amount;
  }

  /// Firestore write that applies the change with atomic increments.
  Map<String, dynamic> toWrite(String monthKey) => {
        'monthKey': monthKey,
        'totalSpent': FieldValue.increment(total),
        'flexibleSpent': FieldValue.increment(flexible),
        'expenseCount': FieldValue.increment(count),
        'spentByCategory': {
          for (final entry in byCategory.entries) entry.key: FieldValue.increment(entry.value),
        },
        'spentByDay': {
          for (final entry in byDay.entries) entry.key: FieldValue.increment(entry.value),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

  MonthStats toStats(String monthKey) => MonthStats(
        monthKey: monthKey,
        totalSpent: total,
        flexibleSpent: flexible,
        expenseCount: count,
        spentByCategory: Map.of(byCategory),
        spentByDay: Map.of(byDay),
      );
}
