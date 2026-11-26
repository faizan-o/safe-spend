import 'package:flutter_test/flutter_test.dart';
import 'package:safespend/models/date_keys.dart';

void main() {
  final date = DateTime(2026, 11, 6, 14, 30);

  test('builds month, day and day-of-month keys', () {
    expect(DateKeys.ofMonth(date), '2026-11');
    expect(DateKeys.ofDay(date), '2026-11-06');
    expect(DateKeys.dayOfMonth(date), '06');
  });

  test('validates month keys', () {
    expect(DateKeys.isValidMonthKey('2026-11'), isTrue);
    expect(DateKeys.isValidMonthKey('2026-13'), isFalse);
    expect(DateKeys.isValidMonthKey('2026-1'), isFalse);
    expect(DateKeys.isValidMonthKey('nope'), isFalse);
    expect(() => DateKeys.startOfMonth('nope'), throwsFormatException);
  });

  test('finds month boundaries', () {
    expect(DateKeys.startOfMonth('2026-11'), DateTime(2026, 11));
    expect(DateKeys.endOfMonthExclusive('2026-11'), DateTime(2026, 12));
    expect(DateKeys.endOfMonthExclusive('2026-12'), DateTime(2027, 1));
  });

  test('counts days in a month, including leap years', () {
    expect(DateKeys.daysInMonth('2026-11'), 30);
    expect(DateKeys.daysInMonth('2026-02'), 28);
    expect(DateKeys.daysInMonth('2028-02'), 29);
  });

  test('steps to the previous and next month across years', () {
    expect(DateKeys.previousMonth('2026-01'), '2025-12');
    expect(DateKeys.nextMonth('2026-12'), '2027-01');
    expect(DateKeys.previousMonth('2026-11'), '2026-10');
  });
}
