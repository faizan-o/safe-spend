/// Settings for the voice workflow.
///
/// The n8n webhook address is not stored in the code. Pass it when you run or
/// build the app:
///
///     flutter run --dart-define=N8N_WEBHOOK_URL=https://your-n8n.example.com/webhook/safespend-voice
///
/// With no address, the app uses a built-in dummy workflow so the whole voice
/// flow can be tried before the real n8n workflow exists.
class VoiceConfig {
  const VoiceConfig._();

  static const String webhookUrl = String.fromEnvironment('N8N_WEBHOOK_URL');

  static bool get hasWebhook => webhookUrl.isNotEmpty;
}
