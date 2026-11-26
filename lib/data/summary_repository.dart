import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/month_summary.dart';

/// Reads and writes users/{uid}/monthSummaries, one report per finished month.
class SummaryRepository {
  SummaryRepository(this._collection);

  final CollectionReference<Map<String, dynamic>> _collection;

  Future<void> saveSummary(MonthSummary summary) {
    return _collection.doc(summary.monthKey).set({
      ...summary.toMap(),
      'generatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<MonthSummary?> watchSummary(String monthKey) {
    return _collection.doc(monthKey).snapshots().map(_parse);
  }

  Future<MonthSummary?> getSummary(String monthKey) async {
    return _parse(await _collection.doc(monthKey).get());
  }

  /// Past summaries, newest month first.
  Stream<List<MonthSummary>> watchSummaries({int limit = 12}) {
    return _collection
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MonthSummary.fromMap(doc.id, doc.data()))
            .toList());
  }

  MonthSummary? _parse(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return null;
    return MonthSummary.fromMap(snapshot.id, data);
  }
}
