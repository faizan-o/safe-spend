import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safespend/models/category.dart';
import 'package:safespend/voice/receipt_client.dart';
import 'package:safespend/voice/voice_models.dart';
import 'package:safespend/voice/voice_workflow_client.dart';

const _categories = [
  ExpenseCategory(id: 'food', name: 'Food', iconKey: 'restaurant', colorValue: 0xFF000000),
  ExpenseCategory(id: 'transport', name: 'Transport', iconKey: 'car', colorValue: 0xFF000000),
  ExpenseCategory(id: 'other', name: 'Other', iconKey: 'category', colorValue: 0xFF000000),
];

VoiceWorkflowRequest _request(String text, {DateTime? at}) => VoiceWorkflowRequest(
      clientRequestId: 'r1',
      userId: 'u1',
      transcript: text,
      localeId: 'en_US',
      sentAt: at ?? DateTime(2026, 11, 26, 14, 30),
      currencyCode: 'PKR',
      currencySymbol: 'Rs.',
      categories: _categories,
    );

void main() {
  test('request JSON follows the documented contract', () {
    final json = _request('spent 500 on lunch').toJson();
    expect(json['source'], 'voice');
    expect(json['transcript'], 'spent 500 on lunch');
    expect(json['localDate'], '2026-11-26');
    expect(json['currency'], {'code': 'PKR', 'symbol': 'Rs.'});
    expect((json['categories'] as List).first, {'id': 'food', 'name': 'Food', 'kind': 'flexible'});
    expect(DateTime.parse(json['sentAt'] as String).isUtc, isTrue);
  });

  test('result parsing: parsed, list-wrapped, unknown status', () {
    final parsed = VoiceWorkflowResult.fromDecoded([
      {
        'status': 'parsed',
        'message': 'ok',
        'expense': {'amount': 1250.5, 'categoryId': 'food', 'date': '2026-11-25'},
      }
    ]);
    expect(parsed.status, VoiceWorkflowStatus.parsed);
    expect(parsed.expense!.amount, 1250.5);
    expect(parsed.expense!.dateOnly, isTrue);

    final unknown = VoiceWorkflowResult.fromDecoded({'status': 'weird'});
    expect(unknown.status, VoiceWorkflowStatus.failed);
    expect(() => VoiceWorkflowResult.fromDecoded('nope'), throwsFormatException);
  });

  test('dummy finds amount, category and yesterday', () async {
    final client = DummyVoiceWorkflowClient(delay: Duration.zero);
    final result = await client.submit(_request('1,200 for groceries yesterday'));
    expect(result.isDummy, isTrue);
    expect(result.status, VoiceWorkflowStatus.parsed);
    expect(result.expense!.amount, 1200);
    expect(result.expense!.date!.day, 25);
  });

  test('dummy asks for the amount when there is none', () async {
    final client = DummyVoiceWorkflowClient(delay: Duration.zero);
    final result = await client.submit(_request('I bought lunch'));
    expect(result.status, VoiceWorkflowStatus.needsClarification);
  });

  group('N8nVoiceWorkflowClient', () {
    test('posts JSON with the bearer token and parses the answer', () async {
      late http.Request seen;
      final client = N8nVoiceWorkflowClient(
        webhookUrl: 'https://example.com/webhook/voice',
        idToken: () async => 'tok',
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'status': 'parsed',
              'expense': {'amount': 500, 'categoryId': 'food'},
            }),
            200,
          );
        }),
      );
      final result = await client.submit(_request('500 lunch'));
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body)['transcript'], '500 lunch');
      expect(result.expense!.amount, 500);
    });

    test('maps server errors and bad JSON to VoiceWorkflowException', () async {
      final server = N8nVoiceWorkflowClient(
        webhookUrl: 'https://example.com/x',
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      expect(server.submit(_request('x')), throwsA(isA<VoiceWorkflowException>()));

      final bad = N8nVoiceWorkflowClient(
        webhookUrl: 'https://example.com/x',
        client: MockClient((_) async => http.Response('not json', 200)),
      );
      expect(bad.submit(_request('x')), throwsA(isA<VoiceWorkflowException>()));
    });
  });

  test('result parsing: saved / review flags, merchant and items', () {
    final r = VoiceWorkflowResult.fromDecoded({
      'status': 'parsed',
      'saved': true,
      'duplicate': true,
      'needsReview': true,
      'reviewReasons': ['low_confidence', 7],
      'expense': {
        'amount': 100,
        'merchant': 'Shop',
        'items': [
          {'description': 'Milk', 'amount': 50, 'quantity': 2},
          {'description': '', 'amount': 5},
        ],
      },
    });
    expect(r.saved, isTrue);
    expect(r.duplicate, isTrue);
    expect(r.needsReview, isTrue);
    expect(r.reviewReasons, ['low_confidence']);
    expect(r.expense!.merchant, 'Shop');
    expect(r.expense!.items.single.quantity, 2);
  });

  test('a 4xx answer shows the workflow\'s own message', () async {
    final client = N8nVoiceWorkflowClient(
      webhookUrl: 'https://example.com/x',
      client: MockClient((_) async => http.Response(jsonEncode({'message': 'Please sign in again.'}), 401)),
    );
    expect(
      client.submit(_request('x')),
      throwsA(isA<VoiceWorkflowException>().having((e) => e.message, 'message', 'Please sign in again.')),
    );
  });

  test('receipt requests carry the picture as base64', () async {
    late Map<String, dynamic> sent;
    final client = N8nReceiptClient(
      url: 'https://example.com/receipt',
      idToken: () async => 't',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'status': 'parsed', 'saved': true, 'expense': {'amount': 10}}), 200);
      }),
    );
    final result = await client.submit(ReceiptRequest(
      clientRequestId: 'r',
      userId: 'u1',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/jpeg',
      sentAt: DateTime(2026, 11, 26),
    ));
    expect(sent['imageBase64'], base64Encode([1, 2, 3]));
    expect(sent['mimeType'], 'image/jpeg');
    expect(result.saved, isTrue);
  });
}
