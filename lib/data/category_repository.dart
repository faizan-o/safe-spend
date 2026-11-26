import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category.dart';

/// Reads and writes users/{uid}/categories.
class CategoryRepository {
  CategoryRepository(this._firestore, this._collection);

  final FirebaseFirestore _firestore;
  final CollectionReference<Map<String, dynamic>> _collection;

  /// Live list of categories in display order. Archived ones are hidden unless
  /// [includeArchived] is true (use that when showing old expenses).
  Stream<List<ExpenseCategory>> watchCategories({bool includeArchived = false}) {
    return _collection
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) => _parse(snapshot, includeArchived));
  }

  Future<List<ExpenseCategory>> getCategories({bool includeArchived = false}) async {
    final snapshot = await _collection.orderBy('sortOrder').get();
    return _parse(snapshot, includeArchived);
  }

  /// Creates a custom category and returns its generated id.
  Future<String> addCategory(ExpenseCategory category) async {
    final ref = _collection.doc();
    await ref.set(category.toMap());
    return ref.id;
  }

  /// Saves changes to an existing category (name, icon, color, order, kind).
  Future<void> updateCategory(ExpenseCategory category) {
    return _collection.doc(category.id).set(category.toMap());
  }

  /// Hides a category without deleting it, so past expenses and summaries
  /// that mention it stay valid.
  Future<void> archiveCategory(String categoryId) {
    return _collection.doc(categoryId).update({'archived': true});
  }

  Future<void> restoreCategory(String categoryId) {
    return _collection.doc(categoryId).update({'archived': false});
  }

  /// Adds the default categories to [batch].
  void queueDefaults(WriteBatch batch) {
    for (final category in defaultCategories) {
      batch.set(_collection.doc(category.id), category.toMap());
    }
  }

  /// Writes the default categories on their own.
  Future<void> seedDefaults() {
    final batch = _firestore.batch();
    queueDefaults(batch);
    return batch.commit();
  }

  List<ExpenseCategory> _parse(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    bool includeArchived,
  ) {
    return snapshot.docs
        .map((doc) => ExpenseCategory.fromMap(doc.id, doc.data()))
        .where((category) => includeArchived || !category.archived)
        .toList();
  }
}
