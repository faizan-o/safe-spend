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
    this.merchant,
    this.items = const [],
    this.date,
    this.dateOnly = false,
  });

  /// In rupees (not paisa), for example 500 or 1250.5.
  final double amount;
  final String? categoryId;
  final String? categoryName;
  final String? note;

  /// Shop or payee, when the workflow found one.
  final String? merchant;

  /// Receipt lines (amounts in rupees).
  final List<ParsedItem> items;

  /// When it was spent; null means now.
  final DateTime? date;

  /// True when the workflow sent only a day ("2026-11-25") and no time.
  final bool dateOnly;
}

/// One receipt line as the workflow reports it (amount in rupees).
class ParsedItem {
  const ParsedItem({required this.description, required this.amount, this.quantity = 1});

  final String description;
  final double amount;
  final int quantity;
}

/// The workflow's answer.
class VoiceWorkflowResult {
  const VoiceWorkflowResult({
    required this.status,
    this.message = '',
    this.expense,
    this.confidence,
    this.workflow,
    this.saved = false,
    this.duplicate = false,
    this.needsReview = false,
    this.reviewReasons = const [],
    this.expenseId,
  });

  /// The id of the expense the workflow saved (when [saved]).
  final String? expenseId;

  /// True when the workflow already stored the expense (and updated the
  /// month totals). The app must not save it again.
  final bool saved;

  /// True when this exact request had already been saved before.
  final bool duplicate;

  /// True when the workflow was not sure enough to save and wants the user
  /// to check the expense first. The app then saves it itself after review.
  final bool needsReview;

  /// Why review is needed, for example `low_confidence` or `category_uncertain`.
  final List<String> reviewReasons;

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
          merchant: _asString(map['merchant']),
          items: [
            for (final raw in map['items'] is List ? map['items'] as List : const [])
              if (raw is Map && _asDouble(raw['amount']) != null && _asString(raw['description']) != null)
                ParsedItem(
                  description: _asString(raw['description'])!,
                  amount: _asDouble(raw['amount'])!,
                  quantity: (_asDouble(raw['quantity']) ?? 1).round().clamp(1, 1000),
                ),
          ],
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
      expenseId: _asString(json['expenseId']),
      saved: json['saved'] == true,
      duplicate: json['duplicate'] == true,
      needsReview: json['needsReview'] == true,
      reviewReasons: [
        for (final reason in json['reviewReasons'] is List ? json['reviewReasons'] as List : const [])
          if (reason is String) reason,
      ],
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
