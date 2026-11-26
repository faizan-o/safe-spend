import 'package:speech_to_text/speech_to_text.dart';

/// A language the speech recognizer can listen in.
class SpeechLocale {
  const SpeechLocale(this.id, this.name);

  /// For example "en_US" or "ur_PK".
  final String id;
  final String name;
}

/// What the voice screen needs from speech-to-text. The app uses
/// [PluginSpeechRecognizer]; tests use a fake one.
abstract class SpeechRecognizer {
  /// Prepares the recognizer and asks for the microphone permission.
  /// Returns false when speech recognition cannot be used.
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  });

  Future<List<SpeechLocale>> locales();

  Future<String?> systemLocaleId();

  /// Starts listening. [onResult] is called with the words heard so far and
  /// whether this is the final result.
  Future<void> start({
    String? localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
  });

  /// Stops listening and delivers the final result.
  Future<void> stop();

  /// Stops listening and throws the result away.
  Future<void> cancel();
}

/// Speech recognition through the phone's own recognizer (the `speech_to_text`
/// package): free, and the audio is handled by the operating system.
class PluginSpeechRecognizer implements SpeechRecognizer {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  }) async {
    try {
      _ready = await _speech.initialize(
        onStatus: onStatus,
        onError: (error) => onError(error.errorMsg),
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<List<SpeechLocale>> locales() async {
    if (!_ready) return const [];
    final list = await _speech.locales();
    return [for (final locale in list) SpeechLocale(locale.localeId, locale.name)];
  }

  @override
  Future<String?> systemLocaleId() async {
    if (!_ready) return null;
    return (await _speech.systemLocale())?.localeId;
  }

  @override
  Future<void> start({
    String? localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
  }) async {
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords, result.finalResult),
      localeId: localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
