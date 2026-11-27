import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/money.dart';
import '../models/receipt.dart';
import '../utils/receipt_image.dart';
import '../voice/receipt_vault.dart';
import '../voice/voice_models.dart';

/// Receipts: a record per receipt in users/{uid}/receipts/{receiptId} (with a
/// tiny thumbnail) and the compressed picture in users/{uid}/receiptImages/{receiptId}.
/// Everything lives in Firestore, so no Firebase Storage (or paid plan) is needed.
///
/// The n8n receipt workflow also writes to the record (in the same atomic
/// commit that saves the expense), so the record is correct even if the app
/// is closed while the workflow is working.
class ReceiptRepository implements ReceiptVault {
  ReceiptRepository(this._collection, this._images);

  final CollectionReference<Map<String, dynamic>> _collection;
  final CollectionReference<Map<String, dynamic>> _images;

  // ---- Reads -------------------------------------------------------------

  /// Receipts, newest first.
  Stream<List<Receipt>> watchReceipts({int limit = 100}) {
    return _collection
        .orderBy('capturedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => [for (final doc in snapshot.docs) Receipt.fromMap(doc.id, doc.data())]);
  }

  /// The full picture, or null when it was not stored.
  Future<Uint8List?> loadImage(String receiptId) async {
    final doc = await _images.doc(receiptId).get();
    final data = doc.data()?['data'];
    return data is Blob ? data.bytes : null;
  }

  // ---- Writes (ReceiptVault) ---------------------------------------------

  @override
  Future<String> store(Uint8List bytes, String mimeType, DateTime capturedAt) async {
    final id = _collection.doc().id;
    // The workflow gets the sharp picture; Firestore keeps a smaller copy.
    final small = await prepareReceiptImage(bytes, mimeType);
    final stored = small.bytes;
    final fits = small.mimeType.startsWith('image/') && stored.length <= maxStoredImageBytes;
    final thumbnail = fits ? await makeThumbnail(stored) : null;

    final batch = FirebaseFirestore.instance.batch();
    if (fits) {
      batch.set(_images.doc(id), {
        'data': Blob(stored),
        'mimeType': small.mimeType,
        'sizeBytes': stored.length,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(_collection.doc(id), {
      'hasImage': fits,
      if (thumbnail != null) 'thumbnail': Blob(thumbnail),
      'mimeType': fits ? small.mimeType : mimeType,
      'sizeBytes': fits ? stored.length : bytes.length,
      'status': ReceiptStatus.processing.name,
      'message': fits ? '' : 'The picture was too large to keep, but it is still being read.',
      'monthKey': DateKeys.ofMonth(capturedAt),
      'capturedAt': Timestamp.fromDate(capturedAt),
      'uploadedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return id;
  }

  @override
  Future<void> recordResult(String receiptId, VoiceWorkflowResult result, {Expense? draft}) {
    final parsed = result.expense;
    final ReceiptStatus status;
    if (result.saved && parsed != null) {
      status = ReceiptStatus.saved;
    } else if (draft != null) {
      status = ReceiptStatus.needsReview;
    } else {
      status = ReceiptStatus.failed;
    }
    return _collection.doc(receiptId).set({
      'status': status.name,
      'message': result.message,
      if (draft != null) ...{
        'amount': draft.amount,
        'categoryId': draft.categoryId,
        'categoryName': draft.categoryName,
        if (draft.merchant != null) 'merchant': draft.merchant,
      } else if (parsed != null) ...{
        'amount': Money.fromMajor(parsed.amount),
        if (parsed.categoryId != null) 'categoryId': parsed.categoryId,
        if (parsed.categoryName != null) 'categoryName': parsed.categoryName,
        if (parsed.merchant != null) 'merchant': parsed.merchant,
      },
      if (result.expenseId != null) 'expenseId': result.expenseId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> markSaved(String receiptId, String expenseId, Expense expense) {
    return _collection.doc(receiptId).set({
      'status': ReceiptStatus.saved.name,
      'expenseId': expenseId,
      'amount': expense.amount,
      'categoryId': expense.categoryId,
      'categoryName': expense.categoryName,
      if (expense.merchant != null) 'merchant': expense.merchant,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Copies what the user changed in the expense (total, category, shop) onto
  /// the receipt record, so the receipt list shows the corrected values.
  Future<void> syncFromExpense(String receiptId, Expense expense) {
    return _collection.doc(receiptId).set({
      'amount': expense.amount,
      'categoryId': expense.categoryId,
      'categoryName': expense.categoryName,
      'merchant': expense.merchant ?? FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> markDiscarded(String receiptId) {
    return _collection.doc(receiptId).set({
      'status': ReceiptStatus.discarded.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> markFailed(String receiptId, String message) {
    return _collection.doc(receiptId).set({
      'status': ReceiptStatus.failed.name,
      'message': message,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes the picture and its record. The expense saved from it stays.
  Future<void> delete(Receipt receipt) async {
    final batch = FirebaseFirestore.instance.batch()
      ..delete(_images.doc(receipt.id))
      ..delete(_collection.doc(receipt.id));
    await batch.commit();
  }
}
