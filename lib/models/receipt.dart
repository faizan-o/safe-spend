import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Blob;

import 'map_readers.dart';

/// Where a receipt is in its life.
enum ReceiptStatus {
  /// Uploaded and being read by the workflow.
  processing,

  /// Read, and the expense was saved.
  saved,

  /// Read, but the workflow was not sure; waiting for the user to check it.
  needsReview,

  /// Could not be read (blurry, not a receipt, or the workflow was down).
  failed,

  /// The user threw the result away.
  discarded,
}

/// A photographed receipt. Stored at users/{uid}/receipts/{receiptId}; the
/// picture itself is a compressed JPEG in
/// users/{uid}/receiptImages/{receiptId}; a small [thumbnail] is kept here.
class Receipt {
  const Receipt({
    required this.id,
    this.hasImage = false,
    this.thumbnail,
    this.mimeType = 'image/jpeg',
    this.sizeBytes = 0,
    this.status = ReceiptStatus.processing,
    this.message = '',
    this.merchant,
    this.amount,
    this.categoryId,
    this.categoryName,
    this.expenseId,
    required this.monthKey,
    this.capturedAt,
    this.uploadedAt,
  });

  final String id;

  /// Whether the picture was stored (false when it was too large or failed).
  final bool hasImage;

  /// Tiny preview for lists.
  final Uint8List? thumbnail;
  final String mimeType;
  final int sizeBytes;
  final ReceiptStatus status;

  /// What the workflow said about it.
  final String message;
  final String? merchant;

  /// Total in minor units, when read.
  final int? amount;
  final String? categoryId;
  final String? categoryName;

  /// The expense saved from this receipt.
  final String? expenseId;
  final String monthKey;

  /// When the picture was taken (device time) and when it was uploaded (server time).
  final DateTime? capturedAt;
  final DateTime? uploadedAt;

  /// The time to show in lists: the server upload time once known.
  DateTime? get timestamp => uploadedAt ?? capturedAt;

  factory Receipt.fromMap(String id, Map<String, dynamic> map) {
    return Receipt(
      id: id,
      hasImage: map['hasImage'] == true,
      thumbnail: map['thumbnail'] is Blob ? (map['thumbnail'] as Blob).bytes : null,
      mimeType: readString(map, 'mimeType', 'image/jpeg'),
      sizeBytes: readInt(map, 'sizeBytes'),
      status: enumByName(ReceiptStatus.values, map['status'], ReceiptStatus.processing),
      message: readString(map, 'message'),
      merchant: readStringOrNull(map, 'merchant'),
      amount: readIntOrNull(map, 'amount'),
      categoryId: readStringOrNull(map, 'categoryId'),
      categoryName: readStringOrNull(map, 'categoryName'),
      expenseId: readStringOrNull(map, 'expenseId'),
      monthKey: readString(map, 'monthKey'),
      capturedAt: readDate(map, 'capturedAt'),
      uploadedAt: readDate(map, 'uploadedAt'),
    );
  }
}
