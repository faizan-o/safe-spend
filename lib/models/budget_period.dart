import 'date_keys.dart';

/// How long a budget lasts.
enum PeriodType { weekly, monthly, yearly, custom }

extension PeriodTypeText on PeriodType {
  String get label => switch (this) {
        PeriodType.weekly => 'Weekly',
        PeriodType.monthly => 'Monthly',
        PeriodType.yearly => 'Yearly',
        PeriodType.custom => 'Custom',
      };
}

/// The dates a budget covers, both ends included (a weekly budget that starts
/// on a Monday ends on the Sunday). Everything is whole local days.
class BudgetPeriod {
  BudgetPeriod({required this.type, required DateTime start, required DateTime end})
      : start = DateKeys.startOfDay(start),
        end = DateKeys.startOfDay(end);

  final PeriodType type;

  /// First day, at local midnight.
  final DateTime start;

  /// Last day (included), at local midnight.
  final DateTime end;

  /// A period of the given type that begins on [start].
  factory BudgetPeriod.starting(PeriodType type, DateTime start) {
    return BudgetPeriod(type: type, start: start, end: endFor(type, start));
  }

  /// The calendar month with this key, e.g. "2026-11".
  factory BudgetPeriod.month(String monthKey) {
    return BudgetPeriod(
      type: PeriodType.monthly,
      start: DateKeys.startOfMonth(monthKey),
      end: DateKeys.addDays(DateKeys.endOfMonthExclusive(monthKey), -1),
    );
  }

  /// The usual first day for a new period of [type] that contains [today]:
  /// the Monday of this week, the 1st of this month, 1 January, or today.
  static DateTime defaultStart(PeriodType type, DateTime today) {
    final day = DateKeys.startOfDay(today);
    return switch (type) {
      PeriodType.weekly => DateKeys.addDays(day, -(day.weekday - 1)),
      PeriodType.monthly => DateTime(day.year, day.month, 1),
      PeriodType.yearly => DateTime(day.year, 1, 1),
      PeriodType.custom => day,
    };
  }

  /// Where a period of [type] that begins on [start] ends. A custom period
  /// has no automatic end, so it is a single day until the user picks one.
  static DateTime endFor(PeriodType type, DateTime start) {
    final first = DateKeys.startOfDay(start);
    return switch (type) {
      PeriodType.weekly => DateKeys.addDays(first, 6),
      PeriodType.monthly => DateKeys.addDays(DateKeys.addMonths(first, 1), -1),
      PeriodType.yearly => DateKeys.addDays(DateKeys.addMonths(first, 12), -1),
      PeriodType.custom => first,
    };
  }

  String get startDay => DateKeys.ofDay(start);
  String get endDay => DateKeys.ofDay(end);

  /// The first moment after the period. Use as an exclusive upper bound.
  DateTime get endExclusive => DateKeys.addDays(end, 1);

  /// Number of days, at least 1.
  int get totalDays {
    final days = DateKeys.daysBetween(start, end) + 1;
    return days < 1 ? 1 : days;
  }

  bool contains(DateTime day) {
    final d = DateKeys.startOfDay(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  bool hasEnded(DateTime today) => DateKeys.startOfDay(today).isAfter(end);

  bool hasNotStarted(DateTime today) => DateKeys.startOfDay(today).isBefore(start);

  /// Which day of the period [day] is: 1 on the first day, [totalDays] on the
  /// last. Days outside the period are clamped to those two.
  int dayNumber(DateTime day) {
    final number = DateKeys.daysBetween(start, day) + 1;
    if (number < 1) return 1;
    if (number > totalDays) return totalDays;
    return number;
  }

  /// Days left including [day] itself.
  int daysLeft(DateTime day) => totalDays - dayNumber(day) + 1;

  /// True when the period is exactly one calendar month (1st to last day).
  bool get isCalendarMonth {
    return start.day == 1 &&
        end.year == start.year &&
        end.month == start.month &&
        end.day == DateKeys.daysInMonth(DateKeys.ofMonth(start));
  }

  /// The period that follows this one. A custom period repeats its own length.
  BudgetPeriod following() {
    final nextStart = DateKeys.addDays(end, 1);
    if (type == PeriodType.custom) {
      return BudgetPeriod(
        type: type,
        start: nextStart,
        end: DateKeys.addDays(nextStart, totalDays - 1),
      );
    }
    return BudgetPeriod.starting(type, nextStart);
  }

  /// The first following period that has not ended before [day]
  /// (this period itself when it already covers [day]).
  BudgetPeriod advancedTo(DateTime day) {
    var period = this;
    var guard = 0;
    while (period.hasEnded(day) && guard < 2000) {
      period = period.following();
      guard++;
    }
    return period;
  }
}
