import '../models/date_keys.dart';
import '../models/debt.dart';
import '../models/month_stats.dart';
import '../models/user_profile.dart';

/// The user's money right now, and how it got there. All amounts are in minor
/// units (paisa).
///
///     balance = opening balance + income - spending + loan movements
///
/// Only what happened from the opening-balance day on counts: the opening
/// balance already includes everything before it.
class BalanceSummary {
  const BalanceSummary({
    required this.since,
    required this.opening,
    required this.income,
    required this.spent,
    required this.loansIn,
    required this.loansOut,
  });

  /// The day the opening balance is true for.
  final DateTime since;
  final int opening;

  /// Income received since [since].
  final int income;

  /// Money spent since [since].
  final int spent;

  /// Money that came in through debts: money borrowed, and loans paid back.
  final int loansIn;

  /// Money that went out through debts: money lent, and debts paid back.
  final int loansOut;

  /// Net effect of debts and loans on the balance.
  int get loanEffect => loansIn - loansOut;

  int get balance => opening + income - spent + loansIn - loansOut;
}

class BalanceCalculator {
  const BalanceCalculator._();

  /// Null while the user has not entered an opening balance.
  ///
  /// [stats] are the stored totals of every month (spending and income by
  /// day). [debts] are all debts; only those that affect the balance count.
  static BalanceSummary? compute({
    required UserProfile? profile,
    required List<MonthStats> stats,
    required List<Debt> debts,
  }) {
    if (profile == null || !profile.hasOpeningBalance) return null;
    final since = DateKeys.parseDay(profile.openingBalanceDay);
    if (since == null) return null;
    final sinceMonth = DateKeys.ofMonth(since);

    var income = 0;
    var spent = 0;
    for (final month in stats) {
      if (!DateKeys.isValidMonthKey(month.monthKey)) continue;
      // Month keys ("2026-11") sort in date order as text.
      final order = month.monthKey.compareTo(sinceMonth);
      if (order < 0) continue;
      if (order == 0) {
        spent += month.spentFromDay(since.day);
        income += month.incomeFromDay(since.day);
      } else {
        spent += month.totalSpent;
        income += month.totalIncome;
      }
    }

    var loansIn = 0;
    var loansOut = 0;
    for (final debt in debts) {
      if (!debt.affectsBalance) continue;
      if (!DateKeys.startOfDay(debt.date).isBefore(since)) {
        if (debt.isOwedToMe) {
          loansOut += debt.amount; // money lent out
        } else {
          loansIn += debt.amount; // money borrowed
        }
      }
      for (final payment in debt.payments) {
        if (DateKeys.startOfDay(payment.date).isBefore(since)) continue;
        if (debt.isOwedToMe) {
          loansIn += payment.amount; // paid back to me
        } else {
          loansOut += payment.amount; // I paid it back
        }
      }
    }

    return BalanceSummary(
      since: since,
      opening: profile.openingBalance,
      income: income,
      spent: spent,
      loansIn: loansIn,
      loansOut: loansOut,
    );
  }

  /// Total still owed by the user across [debts] (open ones only).
  static int totalOwed(List<Debt> debts) => debts
      .where((d) => !d.isOwedToMe)
      .fold<int>(0, (total, d) => total + d.remaining);

  /// Total others still owe the user (open loans only).
  static int totalLent(List<Debt> debts) => debts
      .where((d) => d.isOwedToMe)
      .fold<int>(0, (total, d) => total + d.remaining);
}
