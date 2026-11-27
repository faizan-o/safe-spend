import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/models/category.dart';
import 'package:safespend/models/expense.dart';
import 'package:safespend/voice/receipt_client.dart';
import 'package:safespend/voice/receipt_vault.dart';
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

class FakeVault implements ReceiptVault {
  final List<String> calls = [];

  @override
  Future<String> store(Uint8List bytes, String mimeType, DateTime capturedAt) async {
    calls.add('store');
    return 'rc1';
  }

  @override
  Future<void> recordResult(String receiptId, VoiceWorkflowResult result, {Expense? draft}) async {
    calls.add('result:${draft == null ? 'none' : 'draft'}');
  }

  @override
  Future<void> markSaved(String receiptId, String expenseId, Expense expense) async {
    calls.add('saved:$receiptId:$expenseId');
  }

  @override
  Future<void> markDiscarded(String receiptId) async => calls.add('discarded:$receiptId');

  @override
  Future<void> markFailed(String receiptId, String message) async => calls.add('failed:$receiptId');
}

class FailingClient implements VoiceWorkflowClient {
  @override
  Future<VoiceWorkflowResult> submit(VoiceWorkflowRequest request) =>
      throw const VoiceWorkflowException('down');
}

class SavedByWorkflowClient implements VoiceWorkflowClient {
  @override
  Future<VoiceWorkflowResult> submit(VoiceWorkflowRequest request) async => const VoiceWorkflowResult(
        status: VoiceWorkflowStatus.parsed,
        saved: true,
        expense: ParsedExpense(amount: 500, categoryId: 'food', categoryName: 'Food'),
        workflow: 'n8n-voice',
      );
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
      saveExpense: (e) async {
        saved.add(e);
        return 'exp${saved.length}';
      },
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

  test('an expense the workflow already saved is not saved again', () async {
    final c = make(SavedByWorkflowClient());
    await c.init();
    await c.submitText('500 lunch');
    expect(c.state, VoiceState.ready);
    expect(c.draft, isNull);
    expect(c.notice, contains('Saved'));
    expect(saved, isEmpty);
    c.dispose();
  });

  test('a receipt goes to review and is saved as a receipt expense', () async {
    final c = VoiceController(
      userId: 'u1',
      recognizer: recognizer,
      workflow: DummyVoiceWorkflowClient(delay: Duration.zero),
      receipts: DummyReceiptClient(delay: Duration.zero),
      saveExpense: (e) async {
        saved.add(e);
        return 'exp${saved.length}';
      },
    );
    c.setCategories(const [
      ExpenseCategory(id: 'groceries', name: 'Groceries', iconKey: 'x', colorValue: 0xFF000000),
      ExpenseCategory(id: 'other', name: 'Other', iconKey: 'x', colorValue: 0xFF000000),
    ]);
    await c.init();
    await c.submitReceipt(Uint8List.fromList([1]), 'image/jpeg');
    expect(c.state, VoiceState.result);
    expect(c.result!.needsReview, isTrue);
    expect(c.draft!.source, ExpenseSource.receipt);
    expect(c.draft!.merchant, 'Sample Mart');
    expect(c.draft!.items, hasLength(2));
    expect(c.draft!.transcript, isNull);
    c.save();
    await Future<void>.delayed(Duration.zero);
    expect(saved.single.amount, 125000);
    c.dispose();
  });

  test('a scanned receipt is stored, linked to its expense when saved, and marked discarded otherwise', () async {
    final vault = FakeVault();
    VoiceController build() => VoiceController(
          userId: 'u1',
          recognizer: recognizer,
          workflow: DummyVoiceWorkflowClient(delay: Duration.zero),
          receipts: DummyReceiptClient(delay: Duration.zero),
          vault: vault,
          saveExpense: (e) async {
            saved.add(e);
            return 'exp${saved.length}';
          },
        )..setCategories(const [
            ExpenseCategory(id: 'groceries', name: 'Groceries', iconKey: 'x', colorValue: 0xFF000000),
            ExpenseCategory(id: 'other', name: 'Other', iconKey: 'x', colorValue: 0xFF000000),
          ]);

    final c = build();
    await c.init();
    await c.submitReceipt(Uint8List.fromList([1]), 'image/jpeg');
    expect(c.draft!.receiptId, 'rc1');
    expect(vault.calls, ['store', 'result:draft']);
    c.save();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(vault.calls.last, 'saved:rc1:exp1');
    expect(saved.single.receiptId, 'rc1');

    await c.submitReceipt(Uint8List.fromList([2]), 'image/jpeg');
    c.discard();
    expect(vault.calls.last, 'discarded:rc1');
    c.dispose();
  });
}
