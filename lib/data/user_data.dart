import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'budget_repository.dart';
import 'category_repository.dart';
import 'expense_repository.dart';
import 'firestore_paths.dart';
import 'insight_repository.dart';
import 'receipt_repository.dart';
import 'summary_repository.dart';
import 'user_repository.dart';

/// Everything stored for one signed-in user. Screens get it with
/// `DataScope.of(context)` and use the repositories below:
///
/// ```dart
/// final data = DataScope.of(context);
/// data.expenses.addExpense(...);
/// data.budgets.watchBudget('2026-11');
/// ```
class UserData {
  UserData(this.firestore, this.uid);

  final FirebaseFirestore firestore;
  final String uid;

  late final DocumentReference<Map<String, dynamic>> userDoc =
      firestore.collection(FirestorePaths.users).doc(uid);

  late final CollectionReference<Map<String, dynamic>> _categoriesCol =
      userDoc.collection(FirestorePaths.categories);
  late final CollectionReference<Map<String, dynamic>> _budgetsCol =
      userDoc.collection(FirestorePaths.budgets);
  late final CollectionReference<Map<String, dynamic>> _expensesCol =
      userDoc.collection(FirestorePaths.expenses);
  late final CollectionReference<Map<String, dynamic>> _statsCol =
      userDoc.collection(FirestorePaths.monthStats);
  late final CollectionReference<Map<String, dynamic>> _summariesCol =
      userDoc.collection(FirestorePaths.monthSummaries);
  late final CollectionReference<Map<String, dynamic>> _insightsCol =
      userDoc.collection(FirestorePaths.insights);
  late final CollectionReference<Map<String, dynamic>> _receiptsCol =
      userDoc.collection(FirestorePaths.receipts);

  late final UserRepository profile = UserRepository(userDoc);
  late final CategoryRepository categories =
      CategoryRepository(firestore, _categoriesCol);
  late final BudgetRepository budgets = BudgetRepository(_budgetsCol);
  late final ExpenseRepository expenses =
      ExpenseRepository(firestore, _expensesCol, _statsCol);
  late final SummaryRepository summaries = SummaryRepository(_summariesCol);
  late final InsightRepository insights = InsightRepository(_insightsCol);
  late final CollectionReference<Map<String, dynamic>> _receiptImagesCol =
      userDoc.collection(FirestorePaths.receiptImages);
  late final ReceiptRepository receipts = ReceiptRepository(_receiptsCol, _receiptImagesCol);

  /// Creates the profile and the default categories the first time a user
  /// signs in. Safe to call on every sign-in: it does nothing for an existing
  /// user.
  ///
  /// It asks the server (not the local cache) whether the profile exists. If
  /// the device is offline it does nothing and tries again at the next
  /// sign-in, so a returning user on a new phone is never reset to defaults.
  Future<void> ensureReady(AuthUser user) async {
    UserProfile? existing;
    try {
      existing = await profile.getProfile(serverOnly: true);
    } on FirebaseException catch (error) {
      debugPrint('Skipping first-time setup (server unreachable): ${error.code}');
      return;
    }
    if (existing != null) return;

    final batch = firestore.batch();
    profile.queueCreate(
      batch,
      UserProfile(
        uid: uid,
        name: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : user.firstName,
        email: user.email,
      ),
    );
    categories.queueDefaults(batch);
    await batch.commit();
  }

  /// Deletes every document stored for this user (expenses, budgets,
  /// categories, stats, summaries, insights, receipts with their pictures, and
  /// the profile). Needed for the
  /// in-app "delete my account" option that the app stores require. Deleting
  /// the sign-in account itself is a separate step in the auth service.
  /// Needs the device to be online.
  Future<void> deleteAllData() async {
    for (final collection in [
      _receiptsCol,
      _receiptImagesCol,
      _expensesCol,
      _statsCol,
      _budgetsCol,
      _summariesCol,
      _insightsCol,
      _categoriesCol,
    ]) {
      await _deleteCollection(collection);
    }
    await userDoc.delete();
  }

  Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> collection) async {
    while (true) {
      final snapshot = await collection
          .limit(300)
          .get(const GetOptions(source: Source.server));
      if (snapshot.docs.isEmpty) return;
      final batch = firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
