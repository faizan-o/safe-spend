import '../models/category.dart';
import '../models/date_keys.dart';

/// What the app sends to the n8n workflow after speech-to-text.
/// The full contract is described in docs/voice-n8n.md.
class VoiceWorkflowRequest {
  const VoiceWorkflowRequest({
    required this.clientRequestId,
    required this.userId,
    required this.transcript,
    required this.localeId,
    required this.sentAt,
    required this.currencyCode,
    required this.currencySymbol,
    required this.categories,
  });

  /// Unique per request, so the workflow can ignore a repeated delivery.
  final String clientRequestId;
  final String userId;

  /// What the user said, as text.
  final String transcript;

  /// The speech language, for example "en_US" or "ur_PK" (null = device default).
  final String? localeId;

  /// When the user said it, in local time.
  final DateTime sentAt;
  final String currencyCode;
  final String currencySymbol;

  /// The user's active categories, so the workflow can pick one of them.
  final List<ExpenseCategory> categories;

  Map<String, dynamic> toJson() => {
        'clientRequestId': clientRequestId,
        'userId': userId,
        'source': 'voice',
        'transcript': transcript,
        'locale': localeId,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'localDate': DateKeys.ofDay(sentAt),
        'timeZoneOffsetMinutes': sentAt.timeZoneOffset.inMinutes,
        'currency': {'code': currencyCode, 'symbol': currencySymbol},
        'categories': [
          for (final category in categories)
            {'id': category.id, 'name': category.name, 'kind': category.kind.name},
        ],
      };
}

enum VoiceWorkflowStatus {
  /// The workflow understood the expense.
  parsed,

  /// The workflow needs more information (for example the amount).
  needsClarification,

  /// The workflow could not make sense of it.
  failed,
}

/// The expense the workflow found in the sentence.
class ParsedExpense {
  const ParsedExpense({
    required this.amount,
    this.categoryId,
    this.categoryName,
    this.note,
    this.date,
    this.dateOnly = false,
  });

  /// In rupees (not paisa), for example 500 or 1250.5.
  final double amount;
  final String? categoryId;
  final String? categoryName;
  final String? note;

  /// When it was spent; null means now.
  final DateTime? date;

  /// True when the workflow sent only a day ("2026-11-25") and no time.
  final bool dateOnly;
}

/// The workflow's answer.
class VoiceWorkflowResult {
  const VoiceWorkflowResult({
    required this.status,
    this.message = '',
    this.expense,
    this.confidence,
    this.workflow,
  });

  final VoiceWorkflowStatus status;

  /// A sentence for the user: a confirmation, a question or a reason.
  final String message;
  final ParsedExpense? expense;

  /// From 0 to 1, when the workflow provides it.
  final double? confidence;

  /// Which workflow answered. The built-in dummy answers with "dummy".
  final String? workflow;

  bool get isDummy => workflow == 'dummy';

  /// Reads the JSON the workflow returns. n8n often wraps a response in a
  /// list, so a list with one object is accepted too.
  factory VoiceWorkflowResult.fromDecoded(Object? decoded) {
    Object? value = decoded;
    if (value is List && value.isNotEmpty) value = value.first;
    if (value is! Map) {
      throw const FormatException('The workflow answer is not a JSON object.');
    }
    return VoiceWorkflowResult.fromJson(Map<String, dynamic>.from(value));
  }

  factory VoiceWorkflowResult.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'parsed' => VoiceWorkflowStatus.parsed,
      'needs_clarification' => VoiceWorkflowStatus.needsClarification,
      _ => VoiceWorkflowStatus.failed,
    };

    ParsedExpense? expense;
    final rawExpense = json['expense'];
    if (rawExpense is Map) {
      final map = Map<String, dynamic>.from(rawExpense);
      final amount = _asDouble(map['amount']);
      if (amount != null) {
        final dateText = map['date'];
        expense = ParsedExpense(
          amount: amount,
          categoryId: _asString(map['categoryId']),
          categoryName: _asString(map['categoryName']),
          note: _asString(map['note']),
          date: dateText is String ? DateTime.tryParse(dateText.trim()) : null,
          dateOnly: dateText is String && dateText.trim().length == 10,
        );
      }
    }

    return VoiceWorkflowResult(
      status: status,
      message: _asString(json['message']) ?? '',
      expense: expense,
      confidence: _asDouble(json['confidence']),
      workflow: _asString(json['workflow']),
    );
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '').trim());
    return null;
  }

  static String? _asString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}
