import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'date_keys.dart';
import 'map_readers.dart';

/// Who owes whom.
enum DebtDirection {
  /// The user borrowed money and has to pay it back (a debt).
  owedByMe,

  /// The user lent money and is waiting to get it back (a loan).
  owedToMe,
}

/// A repayment: money paid back toward a debt or received back from a loan.
class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.amount,
    required this.date,
    this.note = '',
  });

  final String id;

  /// Positive amount in minor units.
  final int amount;
  final DateTime date;
  final String note;

  String get dayKey => DateKeys.ofDay(date);

  factory DebtPayment.fromMap(Map<String, dynamic> map) {
    return DebtPayment(
      id: readString(map, 'id'),
      amount: readInt(map, 'amount'),
      date: readDate(map, 'date') ?? DateTime.fromMillisecondsSinceEpoch(0),
      note: readString(map, 'note'),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'date': Timestamp.fromDate(date),
        'note': note,
      };

  DebtPayment copyWith({int? amount, DateTime? date, String? note}) {
    return DebtPayment(
      id: id,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
    );
  }
}

/// Money the user owes someone, or money someone owes the user.
/// Stored at users/{uid}/debts/{id}. The repayments are kept inside the
/// document (there are only ever a handful), so a debt is one small read.
class Debt {
  const Debt({
    this.id = '',
    required this.direction,
    required this.person,
    required this.amount,
    required this.date,
    this.dueDay,
    this.note = '',
    this.payments = const [],
    this.affectsBalance = true,
    this.createdAt,
  });

  final String id;
  final DebtDirection direction;

  /// Who it is with.
  final String person;

  /// The amount borrowed or lent, in minor units.
  final int amount;

  /// The day the money changed hands.
  final DateTime date;

  /// The day it should be paid back by, "yyyy-MM-dd". Null when open-ended.
  final String? dueDay;
  final String note;
  final List<DebtPayment> payments;

  /// Whether the money moving in or out also changes the balance. Turn it off
  /// for a debt that is only being written down, such as one that started
  /// before the opening balance was set.
  final bool affectsBalance;
  final DateTime? createdAt;

  bool get isOwedToMe => direction == DebtDirection.owedToMe;

  /// Total repaid so far.
  int get paid => payments.fold<int>(0, (total, p) => total + p.amount);

  /// What is still unpaid (never below zero).
  int get remaining {
    final left = amount - paid;
    return left < 0 ? 0 : left;
  }

  bool get isSettled => remaining <= 0;

  DateTime? get due => DateKeys.parseDay(dueDay);

  bool isOverdue(DateTime today) {
    final d = due;
    return !isSettled && d != null && DateKeys.startOfDay(today).isAfter(d);
  }

  /// Days until it is due (negative when overdue), or null with no due date.
  int? daysUntilDue(DateTime today) {
    final d = due;
    return d == null ? null : DateKeys.daysBetween(today, d);
  }

  /// Repayment progress from 0 to 1.
  double get progress => amount <= 0 ? 0 : (paid / amount).clamp(0.0, 1.0).toDouble();

  factory Debt.fromMap(String id, Map<String, dynamic> map) {
    return Debt(
      id: id,
      direction: enumByName(DebtDirection.values, map['direction'], DebtDirection.owedByMe),
      person: readString(map, 'person'),
      amount: readInt(map, 'amount'),
      date: readDate(map, 'date') ?? DateTime.fromMillisecondsSinceEpoch(0),
      dueDay: readStringOrNull(map, 'dueDay'),
      note: readString(map, 'note'),
      payments: readMapList(map, 'payments').map(DebtPayment.fromMap).toList(),
      affectsBalance: readBool(map, 'affectsBalance', true),
      createdAt: readDate(map, 'createdAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'direction': direction.name,
        'person': person,
        'amount': amount,
        'date': Timestamp.fromDate(date),
        'dayKey': DateKeys.ofDay(date),
        'dueDay': dueDay,
        'note': note,
        'payments': payments.map((p) => p.toMap()).toList(),
        'paidTotal': paid,
        'affectsBalance': affectsBalance,
      };

  Debt copyWith({
    DebtDirection? direction,
    String? person,
    int? amount,
    DateTime? date,
    String? dueDay,
    bool clearDueDay = false,
    String? note,
    List<DebtPayment>? payments,
    bool? affectsBalance,
  }) {
    return Debt(
      id: id,
      direction: direction ?? this.direction,
      person: person ?? this.person,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      dueDay: clearDueDay ? null : (dueDay ?? this.dueDay),
      note: note ?? this.note,
      payments: payments ?? this.payments,
      affectsBalance: affectsBalance ?? this.affectsBalance,
      createdAt: createdAt,
    );
  }
}
