import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/models/money.dart';

void main() {
  group('Money.parse', () {
    test('reads plain, formatted and prefixed amounts', () {
      expect(Money.parse('500'), 50000);
      expect(Money.parse('1,250.50'), 125050);
      expect(Money.parse('Rs. 500'), 50000);
      expect(Money.parse('  0.5 '), 50);
    });

    test('returns null when there is no valid number', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('1.2.3'), isNull);
    });
  });

  group('Money.format', () {
    test('groups thousands and rounds to whole rupees by default', () {
      expect(Money.format(125050), 'Rs. 1,251');
      expect(Money.format(0), 'Rs. 0');
      expect(Money.format(123456700), 'Rs. 1,234,567');
    });

    test('can show paisa', () {
      expect(Money.format(125050, showDecimals: true), 'Rs. 1,250.50');
      expect(Money.format(5, showDecimals: true), 'Rs. 0.05');
    });

    test('puts the minus sign first', () {
      expect(Money.format(-50000), '-Rs. 500');
    });
  });

  test('fromMajor and toMajor convert both ways', () {
    expect(Money.fromMajor(60000), 6000000);
    expect(Money.toMajor(125050), 1250.5);
  });
}
