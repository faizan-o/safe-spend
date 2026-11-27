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

  /// Parses a day key such as "2026-11-26" into local midnight of that day.
  /// Returns null when the text is not a real date.
  static DateTime? parseDay(String? dayKey) {
    if (dayKey == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dayKey);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    // DateTime rolls 2026-02-31 over to March; reject that.
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  /// Whole calendar days from [from] to [to] (negative when [to] is earlier).
  /// Works on dates, so daylight saving changes never shift the answer.
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// [date] moved by [days] calendar days, at local midnight.
  static DateTime addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  /// [date] moved by [months] months. When the day does not exist in the
  /// target month (31 Jan + 1 month) the last day of that month is used.
  static DateTime addMonths(DateTime date, int months, {int? dayOfMonth}) {
    final wantedDay = dayOfMonth ?? date.day;
    final first = DateTime(date.year, date.month + months);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, wantedDay > lastDay ? lastDay : wantedDay);
  }

  static (int, int) _parse(String monthKey) {
    if (!isValidMonthKey(monthKey)) {
      throw FormatException('Not a month key like "2026-11"', monthKey);
    }
    final parts = monthKey.split('-');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }
}
