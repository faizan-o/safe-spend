import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/debt.dart';

/// Reads and writes users/{uid}/debts: money the user owes and money lent.
///
/// The repayments are stored inside the debt document, so adding, editing or
/// removing one is a single write that also works offline.
class DebtRepository {
  DebtRepository(this._collection);

  final CollectionReference<Map<String, dynamic>> _collection;

  /// Live list. Open debts first (soonest due first), settled ones last.
  Stream<List<Debt>> watchAll() {
    return _collection.snapshots().map((snapshot) => sorted([
          for (final doc in snapshot.docs) Debt.fromMap(doc.id, doc.data()),
        ]));
  }

  /// Orders debts for display: unpaid before settled, then by due date (those
  /// without one last), then newest first.
  static List<Debt> sorted(List<Debt> debts) {
    debts.sort((a, b) {
      if (a.isSettled != b.isSettled) return a.isSettled ? 1 : -1;
      final ad = a.dueDay;
      final bd = b.dueDay;
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      if (ad != null && bd == null) return -1;
      if (ad == null && bd != null) return 1;
      return b.date.compareTo(a.date);
    });
    return debts;
  }

  /// Saves a new debt and returns its id.
  Future<String> add(Debt debt) async {
    _check(debt);
    final ref = _collection.doc();
    await ref.set({
      ...debt.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Saves changes to a debt, including its repayments.
  Future<void> update(Debt debt) {
    if (debt.id.isEmpty) throw ArgumentError('the debt has not been saved');
    _check(debt);
    return _collection.doc(debt.id).update({
      ...debt.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _collection.doc(id).delete();

  /// Records a repayment. Returns the updated debt.
  Future<Debt> addPayment(Debt debt, DebtPayment payment) async {
    if (payment.amount <= 0) {
      throw ArgumentError.value(payment.amount, 'amount', 'must be greater than zero');
    }
    final withId = payment.id.isEmpty
        ? DebtPayment(
            id: _collection.doc().id,
            amount: payment.amount,
            date: payment.date,
            note: payment.note,
          )
        : payment;
    final updated = debt.copyWith(payments: [...debt.payments, withId]);
    await update(updated);
    return updated;
  }

  /// Replaces one repayment (matched by id) with an edited copy.
  Future<Debt> updatePayment(Debt debt, DebtPayment payment) async {
    final updated = debt.copyWith(payments: [
      for (final p in debt.payments) p.id == payment.id ? payment : p,
    ]);
    await update(updated);
    return updated;
  }

  Future<Debt> deletePayment(Debt debt, String paymentId) async {
    final updated = debt.copyWith(payments: [
      for (final p in debt.payments)
        if (p.id != paymentId) p,
    ]);
    await update(updated);
    return updated;
  }

  void _check(Debt debt) {
    if (debt.person.trim().isEmpty) throw ArgumentError('a debt needs a person');
    if (debt.amount <= 0) {
      throw ArgumentError.value(debt.amount, 'amount', 'must be greater than zero');
    }
  }
}
