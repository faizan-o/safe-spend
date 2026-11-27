import 'category.dart';
import 'date_keys.dart';
import 'map_readers.dart';

/// Whether a recurring item is money going out or coming in.
enum RecurringType { expense, income }

/// How often a recurring item repeats. [once] is a single bill with a due
/// date (a school fee, say) that does not repeat.
enum Frequency { once, daily, weekly, monthly, yearly }

extension FrequencyText on Frequency {
  /// "month", "week"...
  String get unit => switch (this) {
        Frequency.once => 'once',
        Frequency.daily => 'day',
        Frequency.weekly => 'week',
        Frequency.monthly => 'month',
        Frequency.yearly => 'year',
      };

  String get label => switch (this) {
        Frequency.once => 'One time',
        Frequency.daily => 'Daily',
        Frequency.weekly => 'Weekly',
        Frequency.monthly => 'Monthly',
        Frequency.yearly => 'Yearly',
      };
}

/// A bill, fee, rent or standing income with a due date.
/// Stored at users/{uid}/recurring/{id}.
///
/// It is not an expense until it is paid. "Mark paid" (or the automatic
/// recording, when [autoRecord] is on) creates the real expense or income and
/// moves [nextDueDay] to the next date.
class RecurringItem {
  const RecurringItem({
    this.id = '',
    required this.title,
    this.type = RecurringType.expense,
    required this.amount,
    this.categoryId,
    this.categoryName,
    this.categoryKind,
    this.frequency = Frequency.monthly,
    this.interval = 1,
    required this.startDay,
    required this.nextDueDay,
    this.endDay,
    this.autoRecord = false,
    this.remindDays = 3,
    this.note = '',
    this.active = true,
    this.lastPaidDay,
    this.createdAt,
  });

  final String id;

  /// "Rent", "Electricity", "School fee"...
  final String title;
  final RecurringType type;

  /// Expected amount in minor units. It can be changed when paying.
  final int amount;

  /// For expenses: the category the payment is recorded under.
  final String? categoryId;
  final String? categoryName;
  final CategoryKind? categoryKind;

  final Frequency frequency;

  /// Repeats every [interval] units ("every 2 weeks"). At least 1.
  final int interval;

  /// The first due date, "yyyy-MM-dd". Its day of the month is kept for
  /// monthly and yearly items ("the 31st" stays the 31st).
  final String startDay;

  /// The next date it is due, "yyyy-MM-dd".
  final String nextDueDay;

  /// After this day it stops repeating. Null means never.
  final String? endDay;

  /// Record it automatically on the due date, without asking.
  final bool autoRecord;

  /// How many days before the due date it counts as "due soon".
  final int remindDays;
  final String note;

  /// False once a one-time item is paid, an item has ended, or the user
  /// paused it.
  final bool active;

  /// The due date that was last paid or recorded.
  final String? lastPaidDay;
  final DateTime? createdAt;

  bool get isIncome => type == RecurringType.income;

  DateTime get nextDue => DateKeys.parseDay(nextDueDay) ?? DateKeys.startOfDay(DateTime.now());

  /// Whole days from [today] to the next due date (negative when overdue).
  int daysUntilDue(DateTime today) => DateKeys.daysBetween(today, nextDue);

  bool isOverdue(DateTime today) => active && daysUntilDue(today) < 0;

  bool isDueSoon(DateTime today) {
    final days = daysUntilDue(today);
    return active && days >= 0 && days <= remindDays;
  }

  /// The due date after [due], or null when this is a one-time item or the
  /// next date would be past [endDay].
  DateTime? dueAfter(DateTime due) {
    final step = interval < 1 ? 1 : interval;
    final anchor = DateKeys.parseDay(startDay) ?? due;
    if (frequency == Frequency.once) return null;
    final next = switch (frequency) {
      Frequency.once => due,
      Frequency.daily => DateKeys.addDays(due, step),
      Frequency.weekly => DateKeys.addDays(due, 7 * step),
      Frequency.monthly => DateKeys.addMonths(due, step, dayOfMonth: anchor.day),
      Frequency.yearly => DateKeys.addMonths(due, 12 * step, dayOfMonth: anchor.day),
    };
    final end = DateKeys.parseDay(endDay);
    if (end != null && next.isAfter(end)) return null;
    return next;
  }

  /// Every due date from [nextDueDay] up to and including [today], oldest
  /// first, at most [limit] of them. Used to catch up on missed dates.
  List<DateTime> duesUpTo(DateTime today, {int limit = 60}) {
    final result = <DateTime>[];
    final end = DateKeys.startOfDay(today);
    DateTime? due = nextDue;
    while (due != null && !due.isAfter(end) && result.length < limit) {
      result.add(due);
      due = dueAfter(due);
    }
    return result;
  }

  factory RecurringItem.fromMap(String id, Map<String, dynamic> map) {
    final kind = map['categoryKind'];
    return RecurringItem(
      id: id,
      title: readString(map, 'title'),
      type: enumByName(RecurringType.values, map['type'], RecurringType.expense),
      amount: readInt(map, 'amount'),
      categoryId: readStringOrNull(map, 'categoryId'),
      categoryName: readStringOrNull(map, 'categoryName'),
      categoryKind: kind is String ? enumByName(CategoryKind.values, kind, CategoryKind.fixed) : null,
      frequency: enumByName(Frequency.values, map['frequency'], Frequency.monthly),
      interval: readInt(map, 'interval', 1),
      startDay: readString(map, 'startDay', DateKeys.ofDay(DateTime.now())),
      nextDueDay: readString(map, 'nextDueDay', DateKeys.ofDay(DateTime.now())),
      endDay: readStringOrNull(map, 'endDay'),
      autoRecord: readBool(map, 'autoRecord'),
      remindDays: readInt(map, 'remindDays', 3),
      note: readString(map, 'note'),
      active: readBool(map, 'active', true),
      lastPaidDay: readStringOrNull(map, 'lastPaidDay'),
      createdAt: readDate(map, 'createdAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'type': type.name,
        'amount': amount,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'categoryKind': categoryKind?.name,
        'frequency': frequency.name,
        'interval': interval,
        'startDay': startDay,
        'nextDueDay': nextDueDay,
        'endDay': endDay,
        'autoRecord': autoRecord,
        'remindDays': remindDays,
        'note': note,
        'active': active,
        'lastPaidDay': lastPaidDay,
      };

  RecurringItem copyWith({
    String? title,
    RecurringType? type,
    int? amount,
    String? categoryId,
    String? categoryName,
    CategoryKind? categoryKind,
    Frequency? frequency,
    int? interval,
    String? startDay,
    String? nextDueDay,
    String? endDay,
    bool clearEndDay = false,
    bool? autoRecord,
    int? remindDays,
    String? note,
    bool? active,
    String? lastPaidDay,
  }) {
    return RecurringItem(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      categoryKind: categoryKind ?? this.categoryKind,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      startDay: startDay ?? this.startDay,
      nextDueDay: nextDueDay ?? this.nextDueDay,
      endDay: clearEndDay ? null : (endDay ?? this.endDay),
      autoRecord: autoRecord ?? this.autoRecord,
      remindDays: remindDays ?? this.remindDays,
      note: note ?? this.note,
      active: active ?? this.active,
      lastPaidDay: lastPaidDay ?? this.lastPaidDay,
      createdAt: createdAt,
    );
  }
}
