import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_insight.dart';

/// Reads and writes users/{uid}/insights, one suggestion per day.
class InsightRepository {
  InsightRepository(this._collection);

  final CollectionReference<Map<String, dynamic>> _collection;

  Future<void> saveInsight(DailyInsight insight) {
    return _collection.doc(insight.dayKey).set({
      ...insight.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DailyInsight?> getInsight(String dayKey) async {
    return _parse(await _collection.doc(dayKey).get());
  }

  Stream<DailyInsight?> watchInsight(String dayKey) {
    return _collection.doc(dayKey).snapshots().map(_parse);
  }

  /// The most recent insight, or null when there are none.
  Stream<DailyInsight?> watchLatest() {
    return _collection
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return DailyInsight.fromMap(doc.id, doc.data());
    });
  }

  DailyInsight? _parse(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return null;
    return DailyInsight.fromMap(snapshot.id, data);
  }
}
