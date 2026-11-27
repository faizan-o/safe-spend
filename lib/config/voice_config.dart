/// Where the n8n workflows live.
///
/// The address is not stored in the code. Pass the base of your n8n webhook
/// URLs (the part before `/safespend/...`) when you run or build the app:
///
///     flutter run --dart-define=N8N_BASE_URL=https://your-n8n.example.com/webhook
///
/// The app then calls `<base>/safespend/voice`, `<base>/safespend/receipt`
/// and `<base>/safespend/report`. With no address, built-in dummy workflows
/// answer voice and receipts so the screens can be tried without n8n, and
/// month reports are unavailable.
class VoiceConfig {
  const VoiceConfig._();

  static const String baseUrl = String.fromEnvironment('N8N_BASE_URL');

  static bool get hasBackend => baseUrl.trim().isNotEmpty;

  static String _url(String name) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/safespend/$name';
  }

  static String get voiceUrl => _url('voice');
  static String get receiptUrl => _url('receipt');
  static String get reportUrl => _url('report');
}
