import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/voice_config.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../services/auth_service.dart';
import 'voice_models.dart';

/// An error whose [message] can be shown to the user.
class VoiceWorkflowException implements Exception {
  const VoiceWorkflowException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sends what the user said to a workflow and returns what it understood.
abstract class VoiceWorkflowClient {
  Future<VoiceWorkflowResult> submit(VoiceWorkflowRequest request);
}

/// The client used by the app: the real n8n webhook when its address was
/// given with --dart-define=N8N_WEBHOOK_URL=..., otherwise the dummy.
VoiceWorkflowClient createVoiceWorkflowClient(AuthService auth) {
  if (VoiceConfig.hasWebhook) {
    return N8nVoiceWorkflowClient(
      webhookUrl: VoiceConfig.webhookUrl,
      idToken: auth.getIdToken,
    );
  }
  return DummyVoiceWorkflowClient();
}

/// Posts the request as JSON to an n8n Webhook node and reads the JSON that
/// its "Respond to Webhook" node returns.
///
/// The user's Firebase ID token is sent as `Authorization: Bearer <token>`, so
/// the workflow can check who is calling instead of trusting a secret that
/// would be stored inside the app.
class N8nVoiceWorkflowClient implements VoiceWorkflowClient {
  N8nVoiceWorkflowClient({
    required this.webhookUrl,
    this.idToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final String webhookUrl;
  final Future<String?> Function()? idToken;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<VoiceWorkflowResult> submit(VoiceWorkflowRequest request) async {
    final token = await idToken?.call();
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(webhookUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Request-Id': request.clientRequestId,
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const VoiceWorkflowException('The workflow took too long to answer. Please try again.');
    } on http.ClientException {
      throw const VoiceWorkflowException('Could not reach the workflow. Check your connection.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceWorkflowException('The workflow returned an error (${response.statusCode}).');
    }

    try {
      return VoiceWorkflowResult.fromDecoded(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException {
      throw const VoiceWorkflowException('The workflow answered in a format the app does not understand.');
    }
  }
}

/// Stands in for the n8n workflow until it exists. It "understands" a sentence
/// with simple rules (the first number is the amount, a keyword picks the
/// category) so the screens can be tried end to end. It answers with the same
/// JSON shape the real workflow will use.
class DummyVoiceWorkflowClient implements VoiceWorkflowClient {
  DummyVoiceWorkflowClient({
    this.delay = const Duration(milliseconds: 1200),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration delay;
  final DateTime Function() _clock;

  static const Map<String, List<String>> _keywords = {
    'food': ['lunch', 'dinner', 'breakfast', 'food', 'restaurant', 'chai', 'tea', 'coffee', 'biryani', 'pizza', 'burger', 'snack', 'snacks'],
    'groceries': ['grocery', 'groceries', 'vegetables', 'sabzi', 'milk', 'fruit', 'fruits', 'eggs'],
    'transport': ['uber', 'careem', 'fuel', 'petrol', 'diesel', 'bus', 'rickshaw', 'taxi', 'metro', 'transport'],
    'shopping': ['shopping', 'clothes', 'shoes', 'shirt', 'bag', 'mall'],
    'entertainment': ['movie', 'cinema', 'netflix', 'game', 'games', 'concert'],
    'health': ['doctor', 'medicine', 'medicines', 'pharmacy', 'hospital', 'clinic'],
    'education': ['fee', 'fees', 'books', 'book', 'tuition', 'course', 'exam'],
    'rent': ['rent'],
    'bills': ['bill', 'bills', 'electricity', 'internet', 'wifi', 'gas', 'water'],
    'committee': ['committee', 'kameti'],
    'savings': ['saved', 'savings'],
  };

  @override
  Future<VoiceWorkflowResult> submit(VoiceWorkflowRequest request) async {
    await Future<void>.delayed(delay);

    final text = request.transcript.trim();
    final amount = _findAmount(text);
    if (amount == null) {
      return const VoiceWorkflowResult(
        status: VoiceWorkflowStatus.needsClarification,
        message: "I couldn't find an amount. How much did you spend?",
        workflow: 'dummy',
      );
    }

    final category = _findCategory(text, request.categories);
    final now = _clock();
    final lower = text.toLowerCase();
    final day = lower.contains('yesterday') ? now.subtract(const Duration(days: 1)) : now;

    return VoiceWorkflowResult(
      status: VoiceWorkflowStatus.parsed,
      message: 'Test mode: understood on the phone. No n8n workflow is connected yet.',
      confidence: 0.5,
      workflow: 'dummy',
      expense: ParsedExpense(
        amount: amount,
        categoryId: category?.id,
        categoryName: category?.name,
        note: text,
        date: DateTime.tryParse(DateKeys.ofDay(day)),
        dateOnly: true,
      ),
    );
  }

  /// The first number in the sentence, with "k", "thousand", "hazar", "lakh"
  /// and "lac" understood: "5k" is 5000.
  double? _findAmount(String text) {
    final match = RegExp(
      r'(\d[\d,]*(?:\.\d+)?)\s*(k|thousand|hazar|lakh|lac)?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (value == null) return null;
    final multiplier = switch (match.group(2)?.toLowerCase()) {
      'k' || 'thousand' || 'hazar' => 1000,
      'lakh' || 'lac' => 100000,
      _ => 1,
    };
    return value * multiplier;
  }

  ExpenseCategory? _findCategory(String text, List<ExpenseCategory> categories) {
    ExpenseCategory? byId(String id) {
      for (final category in categories) {
        if (category.id == id) return category;
      }
      return null;
    }

    final lower = text.toLowerCase();
    for (final entry in _keywords.entries) {
      for (final keyword in entry.value) {
        if (RegExp('\\b${RegExp.escape(keyword)}\\b').hasMatch(lower)) {
          final found = byId(entry.key);
          if (found != null) return found;
        }
      }
    }
    return byId('other');
  }
}
