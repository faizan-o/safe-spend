import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/category.dart';
import '../models/expense.dart';
import '../models/money.dart';
import '../models/user_profile.dart';
import 'speech_recognizer.dart';
import 'voice_models.dart';
import 'voice_workflow_client.dart';

enum VoiceState {
  /// Preparing the microphone and asking for permission.
  initializing,

  /// Waiting for the user to speak or type.
  ready,

  /// The microphone is on.
  listening,

  /// The words were sent to the workflow; waiting for its answer.
  sending,

  /// The workflow answered; the user can save, edit or discard.
  result,
}

/// A language choice shown on the voice screen.
class LanguageOption {
  const LanguageOption(this.label, this.localeId);

  final String label;
  final String localeId;
}

/// Runs the voice flow:
///
///   speak -> speech-to-text -> workflow (n8n, or the dummy) -> review -> save
///
/// The screen listens to this object and shows whatever state it is in.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.userId,
    required this.recognizer,
    required this.workflow,
    required this.saveExpense,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final String userId;
  final SpeechRecognizer recognizer;
  final VoiceWorkflowClient workflow;

  /// Saves the confirmed expense (the app passes the Firestore repository).
  final Future<void> Function(Expense expense) saveExpense;
  final DateTime Function() _now;

  /// Microphone loudness from 0 to 1, for the pulsing ring around the button.
  /// A separate notifier, so the whole screen does not rebuild while speaking.
  final ValueNotifier<double> soundLevel = ValueNotifier<double>(0);

  VoiceState state = VoiceState.initializing;

  /// False when speech recognition is unavailable (no permission, or no
  /// recognizer on the device). Typing still works.
  bool speechAvailable = false;

  /// Why speech is unavailable, for the screen to show.
  String? speechProblem;

  List<LanguageOption> languages = const [];
  String? selectedLocaleId;

  /// The words heard (while listening) or sent (while sending).
  String transcript = '';

  /// The workflow's answer, and the expense built from it.
  VoiceWorkflowResult? result;
  Expense? draft;

  /// A short confirmation to show ("Saved ..."), and an error to show.
  String? notice;
  String? errorMessage;

  List<ExpenseCategory> categories = const [];
  String symbol = 'Rs.';
  String currencyCode = 'PKR';

  Timer? _statusTimer;
  int _requestCounter = 0;
  bool _disposed = false;

  // ---- Context from the rest of the app ------------------------------------

  void setCategories(List<ExpenseCategory> value) {
    categories = value;
    _notify();
  }

  void setProfile(UserProfile? profile) {
    if (profile == null) return;
    symbol = profile.currencySymbol;
    currencyCode = profile.currencyCode;
    _notify();
  }

  // ---- Setup ---------------------------------------------------------------

  Future<void> init() async {
    state = VoiceState.initializing;
    _notify();
    await _initSpeech();
    if (state == VoiceState.initializing) state = VoiceState.ready;
    _notify();
  }

  Future<bool> _initSpeech() async {
    speechAvailable = await recognizer.initialize(onStatus: _onStatus, onError: _onError);
    if (!speechAvailable) {
      speechProblem = 'Voice input is not available. Allow microphone and speech access in '
          'your phone settings, or type what you spent below.';
      return false;
    }
    speechProblem = null;
    await _loadLanguages();
    return true;
  }

  Future<void> _loadLanguages() async {
    final locales = await recognizer.locales();
    final system = await recognizer.systemLocaleId();

    bool matches(String id, String prefix) => id.toLowerCase().replaceAll('-', '_').startsWith(prefix);

    String? english;
    if (system != null && matches(system, 'en')) english = system;
    for (final locale in locales) {
      if (english != null) break;
      if (matches(locale.id, 'en_us')) english = locale.id;
    }
    for (final locale in locales) {
      if (english != null) break;
      if (matches(locale.id, 'en')) english = locale.id;
    }
    String? urdu;
    for (final locale in locales) {
      if (matches(locale.id, 'ur')) {
        urdu = locale.id;
        break;
      }
    }

    languages = [
      if (english != null) LanguageOption('English', english),
      if (urdu != null) LanguageOption('اردو', urdu),
    ];
    selectedLocaleId = english ?? system ?? urdu;
  }

  void selectLanguage(String localeId) {
    if (state == VoiceState.listening || state == VoiceState.sending) return;
    selectedLocaleId = localeId;
    _notify();
  }

  // ---- Listening -----------------------------------------------------------

  /// Starts listening, or stops it when already listening.
  Future<void> toggleListening() async {
    if (state == VoiceState.listening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (state == VoiceState.sending || state == VoiceState.initializing) return;
    if (state == VoiceState.listening) return;

    if (!speechAvailable && !await _initSpeech()) {
      errorMessage = speechProblem;
      _notify();
      return;
    }

    _clearOutput();
    state = VoiceState.listening;
    _notify();
    try {
      await recognizer.start(
        localeId: selectedLocaleId,
        onResult: _onSpeech,
        onLevel: _onLevel,
      );
    } catch (_) {
      _backToReady(error: 'Could not start the microphone. Please try again.');
    }
  }

  /// Stops the microphone. The recognizer then delivers the final words; if it
  /// does not, a short timer finishes the job.
  Future<void> stopListening() async {
    if (state != VoiceState.listening) return;
    try {
      await recognizer.stop();
    } catch (_) {
      // The timer below still finishes the recording.
    }
    _armFinishTimer(const Duration(milliseconds: 1500));
  }

  /// Turns the microphone off without sending anything (used when the screen
  /// is hidden).
  Future<void> cancelListening() async {
    if (state != VoiceState.listening) return;
    _statusTimer?.cancel();
    try {
      await recognizer.cancel();
    } catch (_) {}
    if (_disposed) return;
    transcript = '';
    state = VoiceState.ready;
    soundLevel.value = 0;
    _notify();
  }

  void _onSpeech(String text, bool isFinal) {
    if (_disposed || state != VoiceState.listening) return;
    transcript = text;
    _notify();
    if (isFinal) _finishSpeech();
  }

  void _onLevel(double level) {
    if (_disposed) return;
    // Android reports about -2..10, iOS about -50..0. Map the common range
    // to 0..1; the ring only needs to look alive.
    final normalized = level >= 0 ? (level / 10) : ((level + 2) / 12);
    soundLevel.value = normalized.clamp(0.0, 1.0).toDouble();
  }

  void _onStatus(String status) {
    if (_disposed || state != VoiceState.listening) return;
    if (status == 'done' || status == 'notListening' || status == 'doneNoResult') {
      _armFinishTimer(const Duration(milliseconds: 700));
    }
  }

  void _onError(String error) {
    if (_disposed || state != VoiceState.listening) return;
    _statusTimer?.cancel();
    switch (error) {
      case 'error_no_match':
      case 'error_speech_timeout':
        _backToReady(notice: "I didn't catch that. Tap the mic and try again.");
      case 'error_permission':
        speechAvailable = false;
        speechProblem = 'The microphone is blocked. Allow microphone and speech access in '
            'your phone settings, or type what you spent below.';
        _backToReady(error: speechProblem);
      default:
        _backToReady(error: 'Voice input stopped ($error). Please try again.');
    }
  }

  void _armFinishTimer(Duration after) {
    _statusTimer?.cancel();
    _statusTimer = Timer(after, () {
      if (state == VoiceState.listening) _finishSpeech();
    });
  }

  void _finishSpeech() {
    _statusTimer?.cancel();
    soundLevel.value = 0;
    final text = transcript.trim();
    if (text.isEmpty) {
      _backToReady(notice: "I didn't catch that. Tap the mic and try again.");
      return;
    }
    unawaited(_submit(text));
  }

  // ---- Typing --------------------------------------------------------------

  /// Sends typed text through the same workflow as speech.
  Future<void> submitText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state == VoiceState.sending || state == VoiceState.initializing) return;
    if (state == VoiceState.listening) {
      _statusTimer?.cancel();
      try {
        await recognizer.cancel();
      } catch (_) {}
    }
    await _submit(text);
  }

  // ---- Workflow ------------------------------------------------------------

  Future<void> _submit(String text) async {
    final token = ++_requestCounter;
    _clearOutput();
    transcript = text;
    state = VoiceState.sending;
    _notify();

    try {
      final now = _now();
      final answer = await workflow.submit(VoiceWorkflowRequest(
        clientRequestId: 'req-${now.microsecondsSinceEpoch}',
        userId: userId,
        transcript: text,
        localeId: selectedLocaleId,
        sentAt: now,
        currencyCode: currencyCode,
        currencySymbol: symbol,
        categories: categories,
      ));
      if (_disposed || token != _requestCounter) return; // closed or cancelled while waiting
      result = answer;
      draft = _buildDraft(answer, text);
      state = VoiceState.result;
    } on VoiceWorkflowException catch (error) {
      if (_disposed || token != _requestCounter) return;
      _backToReady(error: error.message, keepTranscript: true);
      return;
    } catch (_) {
      if (_disposed || token != _requestCounter) return;
      _backToReady(error: 'Something went wrong while processing that. Please try again.', keepTranscript: true);
      return;
    }
    _notify();
  }

  /// Gives up on a request that is still waiting for the workflow.
  void cancelSending() {
    if (state != VoiceState.sending) return;
    _requestCounter++;
    _backToReady();
  }

  /// Turns the workflow's answer into an expense that can be saved, or null
  /// when the answer cannot be used.
  Expense? _buildDraft(VoiceWorkflowResult answer, String spoken) {
    final parsed = answer.expense;
    if (answer.status != VoiceWorkflowStatus.parsed || parsed == null) return null;

    final minor = Money.fromMajor(parsed.amount);
    if (minor <= 0) return null;

    final category = _matchCategory(parsed);
    if (category == null) return null;

    return Expense(
      amount: minor,
      categoryId: category.id,
      categoryName: category.name,
      categoryKind: category.kind,
      note: parsed.note ?? '',
      date: _resolveDate(parsed),
      source: ExpenseSource.voice,
      transcript: spoken,
    );
  }

  /// The workflow's category by id, then by name, then "Other", then the first
  /// everyday category.
  ExpenseCategory? _matchCategory(ParsedExpense parsed) {
    final id = parsed.categoryId;
    final name = parsed.categoryName?.toLowerCase();
    for (final category in categories) {
      if (id != null && category.id == id) return category;
    }
    for (final category in categories) {
      if (name != null && category.name.toLowerCase() == name) return category;
    }
    for (final category in categories) {
      if (category.id == 'other') return category;
    }
    for (final category in categories) {
      if (category.kind == CategoryKind.flexible) return category;
    }
    return null;
  }

  DateTime _resolveDate(ParsedExpense parsed) {
    final now = _now();
    var date = parsed.date;
    if (date == null) return now;
    if (parsed.dateOnly) {
      final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
      date = sameDay ? now : DateTime(date.year, date.month, date.day, 12);
    } else {
      date = date.toLocal();
    }
    return date.isAfter(now) ? now : date;
  }

  // ---- Review: save, edit, discard -----------------------------------------

  /// Saves the expense the workflow found.
  void save() {
    final expense = draft;
    if (expense == null || state != VoiceState.result) return;

    // Saved on the device at once and confirmed by the server later, so the
    // screen moves on without waiting (the phone may be offline).
    saveExpense(expense).then((_) {}, onError: (Object _) {
      errorMessage = 'Could not save the expense. Check your connection.';
      _notify();
    });
    markSaved(expense);
  }

  /// Call when the expense was saved some other way (for example after the
  /// user fixed it in the edit sheet; then no [expense] is passed, because the
  /// saved values may differ from the draft).
  void markSaved([Expense? expense]) {
    notice = expense == null
        ? 'Expense saved.'
        : 'Saved ${Money.format(expense.amount, symbol: symbol)} · ${expense.categoryName}';
    result = null;
    draft = null;
    transcript = '';
    errorMessage = null;
    state = VoiceState.ready;
    _notify();
  }

  /// Throws the answer away and goes back to waiting.
  void discard() {
    if (state == VoiceState.sending) {
      cancelSending();
      return;
    }
    _clearOutput();
    transcript = '';
    state = VoiceState.ready;
    _notify();
  }

  // ---- Helpers -------------------------------------------------------------

  void _clearOutput() {
    result = null;
    draft = null;
    notice = null;
    errorMessage = null;
  }

  void _backToReady({String? notice, String? error, bool keepTranscript = false}) {
    if (_disposed) return;
    _statusTimer?.cancel();
    soundLevel.value = 0;
    if (!keepTranscript) transcript = '';
    this.notice = notice;
    errorMessage = error;
    state = VoiceState.ready;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _statusTimer?.cancel();
    soundLevel.dispose();
    super.dispose();
  }
}
