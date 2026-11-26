import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/month_stats.dart';
import '../models/month_summary.dart' show FlagType;
import '../models/monthly_budget.dart';

/// How today's spending compares with today's allowance.
enum DayStatus { onTrack, tight, over }

/// The numbers behind the "safe to spend today" card. All amounts are in
/// minor units (paisa).
///
/// Today's allowance is the everyday money that was left at the start of the
/// day, divided by the days remaining (today included):
///
///     allowance = (pool - spent before today) / days left
///
/// so overspending on one day lowers every following day, and a quiet day
/// raises them.
class DailyBudget {
  const DailyBudget({
    required this.pool,
    required this.spentBeforeToday,
    required this.spentToday,
    required this.daysLeft,
  });

  /// Everyday money for the month: income - fixed bills - savings goal.
  final int pool;

  /// Everyday spending in the month before today.
  final int spentBeforeToday;

  /// Everyday spending today.
  final int spentToday;

  /// Days left in the month, counting today.
  final int daysLeft;

  /// What is left of the month's everyday money (negative = overspent).
  int get remainingPool => pool - spentBeforeToday - spentToday;

  /// How much can be spent today in total.
  int get allowanceToday {
    if (daysLeft <= 0) return 0;
    final available = pool - spentBeforeToday;
    return available <= 0 ? 0 : available ~/ daysLeft;
  }

  /// What is still safe to spend today (negative = over today's allowance).
  int get leftToday => allowanceToday - spentToday;

  /// Share of today's allowance already used, from 0 to 1.
  double get usedFraction {
    if (allowanceToday <= 0) return spentToday > 0 ? 1 : 0;
    return (spentToday / allowanceToday).clamp(0.0, 1.0).toDouble();
  }

  DayStatus get status {
    if (remainingPool < 0 || leftToday < 0) return DayStatus.over;
    if (allowanceToday == 0 || leftToday <= allowanceToday * 0.25) {
      return DayStatus.tight;
    }
    return DayStatus.onTrack;
  }
}

class BudgetCalculator {
  const BudgetCalculator._();

  /// Red and green flags start only from this day of the month. Before it,
  /// one purchase would swing the pace too much to mean anything.
  /// Going over a category's whole limit is flagged on any day.
  static const int minDayForPaceFlags = 5;

  /// A category is red when it is this much ahead of an even spending pace.
  static const double redPace = 1.15;

  /// A category is green when it is this much behind an even spending pace.
  static const double greenPace = 0.85;

  /// Works out today's numbers.
  /// [spentToday] is today's spending in everyday (flexible) categories only.
  static DailyBudget dailyBudget({
    required MonthlyBudget budget,
    required MonthStats stats,
    required int spentToday,
    required DateTime now,
  }) {
    final daysInMonth = DateKeys.daysInMonth(DateKeys.ofMonth(now));
    return DailyBudget(
      pool: budget.flexiblePool,
      spentBeforeToday: stats.flexibleSpent - spentToday,
      spentToday: spentToday,
      daysLeft: daysInMonth - now.day + 1,
    );
  }

  /// Red, green or no flag for one category line.
  /// Only everyday categories with a limit are flagged.
  static FlagType flagFor({
    required CategoryBudget line,
    required int spent,
    required DateTime now,
  }) {
    if (line.kind != CategoryKind.flexible || line.limit <= 0) {
      return FlagType.none;
    }
    if (spent > line.limit) return FlagType.red;
    if (now.day < minDayForPaceFlags) return FlagType.none;

    final daysInMonth = DateKeys.daysInMonth(DateKeys.ofMonth(now));
    final expected = line.limit * now.day / daysInMonth;
    if (spent > expected * redPace) return FlagType.red;
    if (spent <= expected * greenPace) return FlagType.green;
    return FlagType.none;
  }

  /// How much a category should have used by [now] if spending were even.
  static int expectedSpend(CategoryBudget line, DateTime now) {
    final daysInMonth = DateKeys.daysInMonth(DateKeys.ofMonth(now));
    return (line.limit * now.day / daysInMonth).round();
  }

  /// Spending in categories that have no line in the budget.
  static int unbudgetedSpent(MonthlyBudget budget, MonthStats stats) {
    var total = 0;
    stats.spentByCategory.forEach((categoryId, amount) {
      if (budget.forCategory(categoryId) == null) total += amount;
    });
    return total;
  }
}
