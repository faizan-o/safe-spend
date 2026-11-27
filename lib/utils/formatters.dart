import 'package:flutter/material.dart';

import '../models/date_keys.dart';
import '../models/money.dart';
import '../models/budget_period.dart';
import '../models/monthly_budget.dart';

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String monthName(int month) => _monthNames[month - 1];

/// "2026-11" -> "November 2026".
String monthTitle(String monthKey) {
  final start = DateKeys.startOfMonth(monthKey);
  return '${monthName(start.month)} ${start.year}';
}

/// "Today", "Yesterday", or a short date such as "12 Nov" (with the year when
/// it is not the current year).
String dayLabel(DateTime date, DateTime now) {
  final today = DateKeys.startOfDay(now);
  final day = DateKeys.startOfDay(date);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  final short = '${date.day} ${monthName(date.month).substring(0, 3)}';
  return date.year == now.year ? short : '$short ${date.year}';
}

/// "26 Nov 2026, 11:42 PM".
String dateTimeLabel(DateTime date) {
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour < 12 ? 'AM' : 'PM';
  return '${date.day} ${monthName(date.month).substring(0, 3)} ${date.year}, $hour12:$minute $suffix';
}

/// "12 Nov 2026" (always with the year).
String shortDate(DateTime date) =>
    '${date.day} ${monthName(date.month).substring(0, 3)} ${date.year}';

/// "1 Nov – 30 Nov 2026", or "1 Dec 2026 – 30 Nov 2027" across years.
String periodLabel(DateTime start, DateTime end) {
  if (DateKeys.startOfDay(start) == DateKeys.startOfDay(end)) return shortDate(start);
  final startText = start.year == end.year
      ? '${start.day} ${monthName(start.month).substring(0, 3)}'
      : shortDate(start);
  return '$startText – ${shortDate(end)}';
}

/// The name shown for a budget: its title, the month for a calendar-month
/// budget, or "Weekly budget" and so on.
String budgetName(MonthlyBudget budget) {
  if (budget.title.trim().isNotEmpty) return budget.title.trim();
  if (budget.period.isCalendarMonth) return monthTitle(budget.monthKey);
  return '${budget.periodType.label} budget';
}

/// "Overdue by 3 days", "Due today", "Due tomorrow", "Due in 5 days".
String dueText(int daysUntil) {
  if (daysUntil < 0) return 'Overdue by ${plural(-daysUntil, 'day')}';
  if (daysUntil == 0) return 'Due today';
  if (daysUntil == 1) return 'Due tomorrow';
  return 'Due in $daysUntil days';
}

/// An amount with the currency symbol; decimals only when there are any.
String formatMoney(int minor, String symbol) =>
    Money.format(minor, symbol: symbol, showDecimals: minor % 100 != 0);

String plural(int count, String one, [String? many]) {
  return count == 1 ? '$count $one' : '$count ${many ?? '${one}s'}';
}

/// Amount typed into a field when editing, e.g. 50000 -> "500", 125050 -> "1250.50".
String amountForField(int minor) {
  if (minor % 100 == 0) return (minor ~/ 100).toString();
  return (minor / 100).toStringAsFixed(2);
}

/// Colors for the three states used across the dashboard.
class StatusColors {
  const StatusColors._();

  static Color red(BuildContext context) => Theme.of(context).colorScheme.error;

  static Color green(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);
  }
}
