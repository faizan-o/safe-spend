import 'package:flutter/material.dart';

import '../models/date_keys.dart';

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
