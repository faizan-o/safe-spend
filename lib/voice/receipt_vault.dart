import 'dart:typed_data';

import '../models/expense.dart';
import 'voice_models.dart';

/// Keeps the receipt picture and its record. The app uses the Firestore
/// implementation in `ReceiptRepository`; tests use a fake.
abstract class ReceiptVault {
  /// Stores the picture and creates the receipt record (status "processing").
  /// Returns the receipt id. The picture should already be compressed
  /// (see `prepareReceiptImage`); one that is too large is not kept.
  Future<String> store(Uint8List bytes, String mimeType, DateTime capturedAt);

  /// Writes what the workflow answered (saved, needs review or failed).
  Future<void> recordResult(String receiptId, VoiceWorkflowResult result, {Expense? draft});

  /// The user saved the expense that came from this receipt.
  Future<void> markSaved(String receiptId, String expenseId, Expense expense);

  /// The user threw the result away.
  Future<void> markDiscarded(String receiptId);

  /// The request failed before the workflow could answer.
  Future<void> markFailed(String receiptId, String message);
}
