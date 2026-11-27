import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/models/budget_period.dart';
import 'package:safespend/models/debt.dart';
import 'package:safespend/models/recurring.dart';
import 'package:safespend/models/category.dart';
import 'package:safespend/models/expense.dart';
import 'package:safespend/models/month_summary.dart';
import 'package:safespend/models/receipt.dart';

/// The n8n workflows read n8n/schema/safespend.schema.json. These tests fail
/// when the Dart models and that file stop agreeing.
void main() {
  final schema = jsonDecode(File('n8n/schema/safespend.schema.json').readAsStringSync())
      as Map<String, dynamic>;

  test('enums match', () {
    final enums = schema['enums'] as Map<String, dynamic>;
    expect(enums['CategoryKind'], CategoryKind.values.map((e) => e.name).toList());
    expect(enums['ExpenseSource'], ExpenseSource.values.map((e) => e.name).toList());
    expect(enums['FlagType'], FlagType.values.map((e) => e.name).toList());
    expect(enums['ReceiptStatus'], ReceiptStatus.values.map((e) => e.name).toList());
    expect(enums['PeriodType'], PeriodType.values.map((e) => e.name).toList());
    expect(enums['RecurringType'], RecurringType.values.map((e) => e.name).toList());
    expect(enums['Frequency'], Frequency.values.map((e) => e.name).toList());
    expect(enums['DebtDirection'], DebtDirection.values.map((e) => e.name).toList());
  });

  test('default categories match', () {
    final fromFile = [
      for (final c in schema['defaultCategories'] as List)
        '${c['id']}|${c['name']}|${c['kind']}'
    ];
    final fromCode = [for (final c in defaultCategories) '${c.id}|${c.name}|${c.kind.name}'];
    expect(fromFile, fromCode);
  });

  test('expense fields written by the app are all listed', () {
    final doc = (schema['collections'] as Map)['users/{uid}/expenses/{expenseId}'] as Map;
    final known = {
      ...(doc['required'] as List).cast<String>(),
      ...(doc['optional'] as List).cast<String>().map((f) => f.split('[').first),
    };
    final written = Expense(
      amount: 100,
      categoryId: 'food',
      categoryName: 'Food',
      categoryKind: CategoryKind.flexible,
      date: DateTime(2026, 11, 1),
      merchant: 'Shop',
      confidence: 0.9,
      requestId: 'r',
      receiptId: 'rc',
      transcript: 't',
      items: const [ExpenseItem(description: 'x', amount: 100)],
    ).toMap();
    for (final key in written.keys) {
      expect(known, contains(key));
    }
  });

  test('month report survives a round trip', () {
    const report = MonthReport(
      headline: 'h',
      narrative: 'n',
      overspent: [ReportPoint(title: 'Food', detail: 'd', categoryId: 'food')],
      improvements: [ReportAction(title: 't', action: 'a', estimatedSaving: 100000)],
      generatedBy: 'n8n',
    );
    final copy = MonthReport.fromMap(report.toMap());
    expect(copy.overspent.single.categoryId, 'food');
    expect(copy.improvements.single.estimatedSaving, 100000);
  });
}
