import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/date_keys.dart';
import '../models/income.dart';

/// Reads and writes users/{uid}/incomes and keeps the income totals in
/// users/{uid}/monthStats in step with them, in the same atomic batch (the
/// same way [ExpenseRepository] does for spending).
class IncomeRepository {
  IncomeRepository(this._firestore, this._incomes, this._stats);

  final FirebaseFirestore _firestore;
  final CollectionReference<Map<String, dynamic>> _incomes;
  final CollectionReference<Map<String, dynamic>> _stats;

  // ---- Writes ------------------------------------------------------------

  /// Saves a new income and returns its generated id.
  Future<String> addIncome(Income income) async {
    final batch = _firestore.batch();
    final id = queueAdd(batch, income);
    await batch.commit();
    return id;
  }

  /// Adds a new income (and its month totals) to [batch] without committing.
  /// Pass [id] to save under a chosen document id. Returns the id.
  String queueAdd(WriteBatch batch, Income income, {String? id}) {
    _check(income);
    final ref = id == null ? _incomes.doc() : _incomes.doc(id);
    batch.set(ref, {
      ...income.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _queueStats(batch, [(income, 1)]);
    return ref.id;
  }

  /// Saves an edited income. [previous] must be the income as it was before
  /// the edit; it is used to take the old amount out of the totals.
  Future<void> updateIncome({required Income previous, required Income updated}) async {
    if (previous.id.isEmpty || previous.id != updated.id) {
      throw ArgumentError('previous and updated must be the same saved income');
    }
    _check(updated);
    final batch = _firestore.batch()
      ..update(_incomes.doc(updated.id), {
        ...updated.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    _queueStats(batch, [(previous, -1), (updated, 1)]);
    await batch.commit();
  }

  Future<void> deleteIncome(Income income) async {
    if (income.id.isEmpty) throw ArgumentError('income has not been saved');
    final batch = _firestore.batch()..delete(_incomes.doc(income.id));
    _queueStats(batch, [(income, -1)]);
    await batch.commit();
  }

  // ---- Reads -------------------------------------------------------------

  /// Live incomes of a month, newest first.
  Stream<List<Income>> watchMonth(String monthKey) {
    return watchRange(DateKeys.startOfMonth(monthKey), DateKeys.endOfMonthExclusive(monthKey));
  }

  /// Live incomes from [start] up to (not including) [endExclusive], newest first.
  Stream<List<Income>> watchRange(DateTime start, DateTime endExclusive) {
    return _incomes
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(endExclusive))
        .orderBy('date', descending: true)
        .snapshots()
        .map(_parse);
  }

  /// The latest incomes across all months.
  Stream<List<Income>> watchRecent({int limit = 10}) {
    return _incomes.orderBy('date', descending: true).limit(limit).snapshots().map(_parse);
  }

  Future<Income?> getIncome(String id) async {
    final snapshot = await _incomes.doc(id).get();
    final data = snapshot.data();
    return data == null ? null : Income.fromMap(snapshot.id, data);
  }

  Future<bool> exists(String id) async {
    final ref = _incomes.doc(id);
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

  /// Recomputes a month's income totals from its incomes. A repair tool.
  /// Needs the device to be online.
  Future<void> rebuildStats(String monthKey) async {
    final snapshot = await _incomes
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateKeys.startOfMonth(monthKey)))
        .where('date', isLessThan: Timestamp.fromDate(DateKeys.endOfMonthExclusive(monthKey)))
        .get();
    final delta = _IncomeDelta();
    for (final income in _parse(snapshot)) {
      delta.add(income, 1);
    }
    await _stats.doc(monthKey).set(
      {
        'monthKey': monthKey,
        'totalIncome': delta.total,
        'incomeCount': delta.count,
        'incomeByDay': delta.byDay,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(mergeFields: ['monthKey', 'totalIncome', 'incomeCount', 'incomeByDay', 'updatedAt']),
    );
  }

  // ---- Internals ---------------------------------------------------------

  List<Income> _parse(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((doc) => Income.fromMap(doc.id, doc.data())).toList();
  }

  void _check(Income income) {
    if (income.amount <= 0) {
      throw ArgumentError.value(income.amount, 'amount', 'must be greater than zero');
    }
    if (income.source.trim().isEmpty) {
      throw ArgumentError('an income needs a source');
    }
  }

  void _queueStats(WriteBatch batch, List<(Income, int)> changes) {
    final deltas = <String, _IncomeDelta>{};
    for (final (income, sign) in changes) {
      deltas.putIfAbsent(income.monthKey, _IncomeDelta.new).add(income, sign);
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

/// Accumulates how a month's income totals change.
class _IncomeDelta {
  int total = 0;
  int count = 0;
  final Map<String, int> byDay = {};

  void add(Income income, int sign) {
    final amount = income.amount * sign;
    total += amount;
    count += sign;
    final day = DateKeys.dayOfMonth(income.date);
    byDay[day] = (byDay[day] ?? 0) + amount;
  }

  Map<String, dynamic> toWrite(String monthKey) => {
        'monthKey': monthKey,
        'totalIncome': FieldValue.increment(total),
        'incomeCount': FieldValue.increment(count),
        'incomeByDay': {
          for (final entry in byDay.entries) entry.key: FieldValue.increment(entry.value),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
