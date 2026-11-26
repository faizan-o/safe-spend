import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/models/category.dart';
import 'package:safespend/models/expense.dart';
import 'package:safespend/voice/speech_recognizer.dart';
import 'package:safespend/voice/voice_controller.dart';
import 'package:safespend/voice/voice_models.dart';
import 'package:safespend/voice/voice_workflow_client.dart';

class FakeRecognizer implements SpeechRecognizer {
  bool available = true;
  void Function(String, bool)? _onResult;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  }) async =>
      available;

  @override
  Future<List<SpeechLocale>> locales() async =>
      const [SpeechLocale('en_US', 'English'), SpeechLocale('ur_PK', 'Urdu')];

  @override
  Future<String?> systemLocaleId() async => 'en_US';

  @override
  Future<void> start({
    String? localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
  }) async {
    _onResult = onResult;
  }

  void say(String text) => _onResult?.call(text, true);

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

class FailingClient implements VoiceWorkflowClient {
  @override
  Future<VoiceWorkflowResult> submit(VoiceWorkflowRequest request) =>
      throw const VoiceWorkflowException('down');
}

const _categories = [
  ExpenseCategory(id: 'food', name: 'Food', iconKey: 'restaurant', colorValue: 0xFF000000),
  ExpenseCategory(id: 'other', name: 'Other', iconKey: 'category', colorValue: 0xFF000000),
];

void main() {
  late FakeRecognizer recognizer;
  late List<Expense> saved;

  VoiceController make([VoiceWorkflowClient? client]) {
    final c = VoiceController(
      userId: 'u1',
      recognizer: recognizer,
      workflow: client ?? DummyVoiceWorkflowClient(delay: Duration.zero),
      saveExpense: (e) async => saved.add(e),
    );
    c.setCategories(_categories);
    return c;
  }

  setUp(() {
    recognizer = FakeRecognizer();
    saved = [];
  });

  test('init makes the controller ready', () async {
    final c = make();
    await c.init();
    expect(c.state, VoiceState.ready);
    expect(c.speechAvailable, isTrue);
    c.dispose();
  });

  test('speech unavailable still allows typing', () async {
    recognizer.available = false;
    final c = make();
    await c.init();
    expect(c.speechAvailable, isFalse);
    await c.submitText('300 lunch');
    expect(c.state, VoiceState.result);
    expect(c.draft, isNotNull);
    c.dispose();
  });

  test('typed text becomes a draft that can be saved', () async {
    final c = make();
    await c.init();
    await c.submitText('Spent 500 on lunch');
    expect(c.state, VoiceState.result);
    expect(c.draft!.amount, 50000);
    expect(c.draft!.categoryId, 'food');
    c.save();
    await Future<void>.delayed(Duration.zero);
    expect(saved, hasLength(1));
    expect(saved.single.source, ExpenseSource.voice);
    c.dispose();
  });

  test('no amount gives no draft', () async {
    final c = make();
    await c.init();
    await c.submitText('bought lunch');
    expect(c.state, VoiceState.result);
    expect(c.draft, isNull);
    c.dispose();
  });

  test('a workflow error is shown and the user can retry', () async {
    final c = make(FailingClient());
    await c.init();
    await c.submitText('500 lunch');
    expect(c.errorMessage, isNotNull);
    expect(c.state, VoiceState.ready);
    c.dispose();
  });

  test('discard returns to ready', () async {
    final c = make();
    await c.init();
    await c.submitText('500 lunch');
    c.discard();
    expect(c.state, VoiceState.ready);
    expect(c.draft, isNull);
    c.dispose();
  });
}
