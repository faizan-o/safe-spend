import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/recurring.dart';
import 'expense_repository.dart';
import 'income_repository.dart';

/// Reads and writes users/{uid}/recurring: bills, rent, fees and standing
/// income with due dates.
///
/// Paying one (by hand, or automatically on its due date) creates a normal
/// expense or income and moves the item to its next due date in the same
/// atomic batch. The expense id is built from the item and the due date, so
/// the same due date can never be recorded twice, even if two devices both
/// try.
class RecurringRepository {
  RecurringRepository(this._firestore, this._collection, this._expenses, this._incomes);

  final FirebaseFirestore _firestore;
  final CollectionReference<Map<String, dynamic>> _collection;
  final ExpenseRepository _expenses;
  final IncomeRepository _incomes;

  // ---- Reads -------------------------------------------------------------

  /// Live list, soonest due first. Items that are no longer active go last.
  Stream<List<RecurringItem>> watchAll() {
    return _collection.snapshots().map((snapshot) => _sorted(_parse(snapshot)));
  }

  Future<List<RecurringItem>> getAll() async {
    return _sorted(_parse(await _collection.get()));
  }

  // ---- Writes ------------------------------------------------------------

  /// Saves a new item and returns its id.
  Future<String> add(RecurringItem item) async {
    _check(item);
    final ref = _collection.doc();
    await ref.set({
      ...item.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(RecurringItem item) {
    if (item.id.isEmpty) throw ArgumentError('the item has not been saved');
    _check(item);
    return _collection.doc(item.id).update({
      ...item.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes the item. Expenses already recorded from it stay.
  Future<void> delete(String id) => _collection.doc(id).delete();

  /// Pauses or resumes an item.
  Future<void> setActive(RecurringItem item, bool active) {
    return _collection.doc(item.id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Records the item's current due date as paid and moves to the next one.
  ///
  /// The expense (or income) is dated [paidOn] (today by default) and uses
  /// [amount] (the item's amount by default), so the real amount of a bill can
  /// be entered. Does nothing twice for the same due date.
  Future<void> markPaid(
    RecurringItem item, {
    int? amount,
    DateTime? paidOn,
    String? note,
  }) async {
    final due = item.nextDue;
    final batch = _firestore.batch();
    await _queueOccurrence(
      batch,
      item,
      due,
      amount: amount ?? item.amount,
      when: paidOn ?? DateTime.now(),
      note: note,
    );
    _queueAdvance(batch, item, due);
    // When this due date had already been recorded nothing is added, but the
    // item still moves on, which is what the user asked for.
    await batch.commit();
  }

  /// Moves to the next due date without recording anything (a bill that did
  /// not have to be paid this time).
  Future<void> skip(RecurringItem item) {
    final batch = _firestore.batch();
    _queueAdvance(batch, item, item.nextDue);
    return batch.commit();
  }

  /// Records every automatic item that has come due, including dates missed
  /// while the app was closed. Safe to call as often as you like. Returns how
  /// many expenses and incomes were recorded.
  ///
  /// The writes are queued on the device and synced later, so this does not
  /// wait for the network.
  Future<int> recordDue({DateTime? now}) async {
    final today = DateKeys.startOfDay(now ?? DateTime.now());
    final items = await getAll();
    var recorded = 0;
    for (final item in items) {
      if (!item.active || !item.autoRecord) continue;
      final dues = item.duesUpTo(today);
      if (dues.isEmpty) continue;

      final batch = _firestore.batch();
      for (final due in dues) {
        final made = await _queueOccurrence(
          batch,
          item,
          due,
          amount: item.amount,
          // Dated on the due date itself, at midday.
          when: DateTime(due.year, due.month, due.day, 12),
        );
        if (made) recorded++;
      }
      _queueAdvance(batch, item, dues.last);
      batch.commit().then((_) {}, onError: (Object _) {});
    }
    return recorded;
  }

  // ---- Internals ---------------------------------------------------------

  /// The id of the expense or income recorded for one due date.
  static String occurrenceId(String itemId, DateTime due) => 'rec_${itemId}_${DateKeys.ofDay(due)}';

  /// Adds the expense or income for one due date to [batch]. Returns false
  /// (and adds nothing) when that due date was already recorded.
  Future<bool> _queueOccurrence(
    WriteBatch batch,
    RecurringItem item,
    DateTime due, {
    required int amount,
    required DateTime when,
    String? note,
  }) async {
    final id = occurrenceId(item.id, due);
    final date = DateTime(when.year, when.month, when.day, when.hour, when.minute);
    if (item.isIncome) {
      if (await _incomes.exists(id)) return false;
      _incomes.queueAdd(
        batch,
        Income(
          amount: amount,
          source: item.title,
          note: note ?? item.note,
          date: date,
          recurringId: item.id,
        ),
        id: id,
      );
    } else {
      if (await _expenses.exists(id)) return false;
      _expenses.queueAdd(
        batch,
        Expense(
          amount: amount,
          categoryId: item.categoryId ?? 'bills',
          categoryName: item.categoryName ?? 'Bills & utilities',
          categoryKind: item.categoryKind ?? CategoryKind.fixed,
          note: (note != null && note.isNotEmpty) ? note : item.title,
          date: date,
          recurringId: item.id,
        ),
        id: id,
      );
    }
    return true;
  }

  /// Moves [item] on from the due date [paidDue]: to the next date, or to
  /// finished when there is none.
  void _queueAdvance(WriteBatch batch, RecurringItem item, DateTime paidDue) {
    final next = item.dueAfter(paidDue);
    batch.update(_collection.doc(item.id), {
      'nextDueDay': DateKeys.ofDay(next ?? paidDue),
      'active': next != null,
      'lastPaidDay': DateKeys.ofDay(paidDue),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _check(RecurringItem item) {
    if (item.title.trim().isEmpty) throw ArgumentError('a bill needs a name');
    if (item.amount <= 0) {
      throw ArgumentError.value(item.amount, 'amount', 'must be greater than zero');
    }
    if (DateKeys.parseDay(item.nextDueDay) == null || DateKeys.parseDay(item.startDay) == null) {
      throw ArgumentError('the due date is not a valid date');
    }
  }

  List<RecurringItem> _parse(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return [for (final doc in snapshot.docs) RecurringItem.fromMap(doc.id, doc.data())];
  }

  List<RecurringItem> _sorted(List<RecurringItem> items) {
    items.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      final byDue = a.nextDueDay.compareTo(b.nextDueDay);
      return byDue != 0 ? byDue : a.title.compareTo(b.title);
    });
    return items;
  }
}
