import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/voice_config.dart';
import '../services/auth_service.dart';
import 'voice_models.dart';
import 'voice_workflow_client.dart';

/// A photo (or PDF) of a receipt, bill or payment screenshot.
class ReceiptRequest {
  const ReceiptRequest({
    required this.clientRequestId,
    required this.userId,
    required this.bytes,
    required this.mimeType,
    required this.sentAt,
    this.receiptId,
  });

  final String clientRequestId;
  final String userId;
  final Uint8List bytes;

  /// image/jpeg, image/png, image/webp, image/gif or application/pdf.
  final String mimeType;
  final DateTime sentAt;

  /// The receipt record this picture belongs to. The workflow links the saved
  /// expense to it.
  final String? receiptId;

  Map<String, dynamic> toJson() => {
        'clientRequestId': clientRequestId,
        'userId': userId,
        'source': 'receipt',
        if (receiptId != null) 'receiptId': receiptId,
        'imageBase64': base64Encode(bytes),
        'mimeType': mimeType,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'timeZoneOffsetMinutes': sentAt.timeZoneOffset.inMinutes,
      };
}

/// Reads a receipt and answers in the same format as the voice workflow.
abstract class ReceiptClient {
  Future<VoiceWorkflowResult> submit(ReceiptRequest request);
}

/// The n8n receipt workflow when [VoiceConfig.baseUrl] is set, otherwise a dummy.
ReceiptClient createReceiptClient(AuthService auth) {
  if (VoiceConfig.hasBackend) {
    return N8nReceiptClient(url: VoiceConfig.receiptUrl, idToken: auth.getIdToken);
  }
  return DummyReceiptClient();
}

class N8nReceiptClient implements ReceiptClient {
  N8nReceiptClient({
    required this.url,
    this.idToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client();

  final String url;
  final Future<String?> Function()? idToken;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<VoiceWorkflowResult> submit(ReceiptRequest request) async {
    final decoded = await postWorkflowJson(
      client: _client,
      url: url,
      body: request.toJson(),
      requestId: request.clientRequestId,
      token: await idToken?.call(),
      timeout: timeout,
    );
    try {
      return VoiceWorkflowResult.fromDecoded(decoded);
    } on FormatException {
      throw const VoiceWorkflowException('The workflow answered in a format the app does not understand.');
    }
  }
}

/// Stands in for the receipt workflow when no n8n address is configured. It
/// ignores the picture and answers with a fixed sample so the screens can be
/// tried.
class DummyReceiptClient implements ReceiptClient {
  DummyReceiptClient({this.delay = const Duration(milliseconds: 1500), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration delay;
  final DateTime Function() _clock;

  @override
  Future<VoiceWorkflowResult> submit(ReceiptRequest request) async {
    await Future<void>.delayed(delay);
    final now = _clock();
    return VoiceWorkflowResult(
      status: VoiceWorkflowStatus.parsed,
      message: 'Test mode: this is a sample result. Connect n8n to read real receipts.',
      confidence: 0.5,
      workflow: 'dummy',
      needsReview: true,
      reviewReasons: const ['low_confidence'],
      expense: ParsedExpense(
        amount: 1250,
        categoryId: 'groceries',
        categoryName: 'Groceries',
        merchant: 'Sample Mart',
        note: 'Sample Mart',
        items: const [
          ParsedItem(description: 'Milk', amount: 450, quantity: 2),
          ParsedItem(description: 'Rice', amount: 800),
        ],
        date: DateTime(now.year, now.month, now.day),
        dateOnly: true,
      ),
    );
  }
}
