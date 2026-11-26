/// Keys used to group data by month and day.
///
/// A month key looks like "2026-11" and is used as the document id of that
/// month's budget, stats and summary. A day key looks like "2026-11-26".
/// Keys are built from the device's local date.
class DateKeys {
  const DateKeys._();

  static String ofMonth(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  static String ofDay(DateTime date) =>
      '${ofMonth(date)}-${date.day.toString().padLeft(2, '0')}';

  /// Two-digit day of month ("05"), used as the key inside a month's stats.
  static String dayOfMonth(DateTime date) => date.day.toString().padLeft(2, '0');

  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool isValidMonthKey(String key) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key);
    if (match == null) return false;
    final month = int.parse(match.group(2)!);
    return month >= 1 && month <= 12;
  }

  /// First moment of the month, e.g. "2026-11" -> 2026-11-01 00:00 local.
  static DateTime startOfMonth(String monthKey) {
    final parts = _parse(monthKey);
    return DateTime(parts.$1, parts.$2);
  }

  /// First moment of the following month. Use as an exclusive upper bound.
  static DateTime endOfMonthExclusive(String monthKey) {
    final parts = _parse(monthKey);
    return DateTime(parts.$1, parts.$2 + 1);
  }

  static int daysInMonth(String monthKey) {
    final parts = _parse(monthKey);
    return DateTime(parts.$1, parts.$2 + 1, 0).day;
  }

  static String previousMonth(String monthKey) {
    final parts = _parse(monthKey);
    return ofMonth(DateTime(parts.$1, parts.$2 - 1));
  }

  static String nextMonth(String monthKey) {
    final parts = _parse(monthKey);
    return ofMonth(DateTime(parts.$1, parts.$2 + 1));
  }

  static (int, int) _parse(String monthKey) {
    if (!isValidMonthKey(monthKey)) {
      throw FormatException('Not a month key like "2026-11"', monthKey);
    }
    final parts = monthKey.split('-');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }
}
