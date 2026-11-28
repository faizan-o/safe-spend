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

  /// Why the last call was skipped (for example `no_data`, `already_generated`
  /// or `error: ...`), when the workflow said.
  String? get lastReason;

  /// The finished report (a plain map) from the last `generated` call. The
  /// app saves it; the workflow only writes it itself on its monthly schedule.
  Map<String, dynamic>? get lastSummary;

  /// Returns the workflow's status: `generated` or `skipped` (nothing to
  /// report for that month). [data] is the month's numbers read by the app
  /// (budget, totals, expenses), so the workflow needs no database access.
  /// Throws [VoiceWorkflowException] on failure.
  Future<String> generate(String monthKey, {Map<String, dynamic>? data});
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
  String? lastReason;

  @override
  Map<String, dynamic>? lastSummary;

  @override
  Future<String> generate(String monthKey, {Map<String, dynamic>? data}) async {
    lastSummary = null;
    if (!DateKeys.isValidMonthKey(monthKey)) {
      throw const VoiceWorkflowException('That month is not valid.');
    }
    final decoded = await postWorkflowJson(
      client: _client,
      url: url,
      body: {'userId': userId, 'monthKey': monthKey, 'force': true, if (data != null) 'data': data},
      requestId: 'report-$monthKey-${DateTime.now().microsecondsSinceEpoch}',
      token: await idToken?.call(),
      timeout: timeout,
    );
    lastReason = decoded is Map && decoded['reason'] is String ? decoded['reason'] as String : null;
    final status = decoded is Map && decoded['status'] is String ? decoded['status'] as String : 'failed';
    if (status == 'generated' && decoded is Map && decoded['summary'] is Map) {
      lastSummary = Map<String, dynamic>.from(decoded['summary'] as Map);
    }
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
  String? get lastReason => null;

  @override
  Map<String, dynamic>? get lastSummary => null;

  @override
  Future<String> generate(String monthKey, {Map<String, dynamic>? data}) {
    throw const VoiceWorkflowException(
      'Reports need the n8n workflow. Run the app with --dart-define=N8N_BASE_URL=... to enable them.',
    );
  }
}
