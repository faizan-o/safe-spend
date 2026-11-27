import 'package:http/http.dart' as http;

import '../config/voice_config.dart';
import '../models/date_keys.dart';
import '../services/auth_service.dart';
import '../voice/voice_workflow_client.dart';

/// Asks the n8n report workflow to (re)generate a month's report. The report
/// itself is saved to Firestore by the workflow, so the screen simply watches
/// `monthSummaries/{monthKey}` and updates when it appears.
abstract class ReportClient {
  /// False when no n8n address is configured.
  bool get available;

  /// Returns the workflow's status: `generated` or `skipped` (nothing to
  /// report for that month). Throws [VoiceWorkflowException] on failure.
  Future<String> generate(String monthKey);
}

ReportClient createReportClient(AuthService auth, String userId) {
  if (VoiceConfig.hasBackend) {
    return N8nReportClient(url: VoiceConfig.reportUrl, userId: userId, idToken: auth.getIdToken);
  }
  return UnavailableReportClient();
}

class N8nReportClient implements ReportClient {
  N8nReportClient({
    required this.url,
    required this.userId,
    this.idToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 120),
  }) : _client = client ?? http.Client();

  final String url;
  final String userId;
  final Future<String?> Function()? idToken;
  final Duration timeout;
  final http.Client _client;

  @override
  bool get available => true;

  @override
  Future<String> generate(String monthKey) async {
    if (!DateKeys.isValidMonthKey(monthKey)) {
      throw const VoiceWorkflowException('That month is not valid.');
    }
    final decoded = await postWorkflowJson(
      client: _client,
      url: url,
      body: {'userId': userId, 'monthKey': monthKey, 'force': true},
      requestId: 'report-$monthKey-${DateTime.now().microsecondsSinceEpoch}',
      token: await idToken?.call(),
      timeout: timeout,
    );
    final status = decoded is Map && decoded['status'] is String ? decoded['status'] as String : 'failed';
    if (status == 'failed') {
      final message = decoded is Map && decoded['message'] is String ? decoded['message'] as String : null;
      throw VoiceWorkflowException(message ?? 'The report could not be generated. Please try again.');
    }
    return status;
  }
}

class UnavailableReportClient implements ReportClient {
  @override
  bool get available => false;

  @override
  Future<String> generate(String monthKey) {
    throw const VoiceWorkflowException(
      'Reports need the n8n workflow. Run the app with --dart-define=N8N_BASE_URL=... to enable them.',
    );
  }
}
