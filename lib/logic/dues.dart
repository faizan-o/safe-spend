import '../models/date_keys.dart';
import '../models/debt.dart';
import '../models/recurring.dart';

/// What kind of thing is due.
enum DueKind {
  /// A bill, fee or rent to pay.
  bill,

  /// Income that is expected (a salary).
  income,

  /// A debt the user has to pay back.
  debtToPay,

  /// A loan the user is waiting to get back.
  loanToCollect,
}

/// One line in "what is coming up": a bill, an expected income or a debt with
/// a due date.
class DueItem {
  const DueItem({
    required this.kind,
    required this.title,
    required this.amount,
    required this.due,
    required this.daysUntil,
    this.recurring,
    this.debt,
  });

  final DueKind kind;
  final String title;

  /// Amount due in minor units (for a debt, what is still unpaid).
  final int amount;
  final DateTime due;

  /// Days from today to the due date; negative when overdue.
  final int daysUntil;

  /// The bill this line comes from, when it is a bill or an expected income.
  final RecurringItem? recurring;

  /// The debt this line comes from, when it is a debt or a loan.
  final Debt? debt;

  bool get overdue => daysUntil < 0;
  bool get isMoneyIn => kind == DueKind.income || kind == DueKind.loanToCollect;
}

class Dues {
  const Dues._();

  /// Everything with a due date, soonest first (overdue items come first).
  /// Paused and finished bills and settled debts are left out. With
  /// [withinDays], items due later than that many days from [today] are left
  /// out too (overdue items always stay).
  static List<DueItem> build({
    required List<RecurringItem> recurring,
    required List<Debt> debts,
    required DateTime today,
    int? withinDays,
  }) {
    final day = DateKeys.startOfDay(today);
    final items = <DueItem>[];

    for (final item in recurring) {
      if (!item.active) continue;
      items.add(DueItem(
        kind: item.isIncome ? DueKind.income : DueKind.bill,
        title: item.title,
        amount: item.amount,
        due: item.nextDue,
        daysUntil: item.daysUntilDue(day),
        recurring: item,
      ));
    }

    for (final debt in debts) {
      final due = debt.due;
      if (debt.isSettled || due == null) continue;
      items.add(DueItem(
        kind: debt.isOwedToMe ? DueKind.loanToCollect : DueKind.debtToPay,
        title: debt.person,
        amount: debt.remaining,
        due: due,
        daysUntil: DateKeys.daysBetween(day, due),
        debt: debt,
      ));
    }

    items.sort((a, b) => a.due.compareTo(b.due));
    if (withinDays == null) return items;
    return [for (final item in items) if (item.daysUntil <= withinDays) item];
  }
}
