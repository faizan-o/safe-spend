import 'package:flutter/material.dart';

import '../../logic/budget_calculator.dart';
import '../../models/money.dart';
import '../../utils/formatters.dart';

/// The main number: how much is still safe to spend today.
class SafeToSpendCard extends StatelessWidget {
  const SafeToSpendCard({super.key, required this.daily, required this.symbol});

  final DailyBudget daily;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Color background;
    final Color foreground;
    final String message;
    switch (daily.status) {
      case DayStatus.onTrack:
        background = scheme.primaryContainer;
        foreground = scheme.onPrimaryContainer;
        message = "You're on track for today.";
      case DayStatus.tight:
        background = scheme.tertiaryContainer;
        foreground = scheme.onTertiaryContainer;
        message = "Getting close to today's limit.";
      case DayStatus.over:
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
        message = "Over today's limit. Tomorrow's number will shrink.";
    }

    final left = daily.leftToday;
    final headline = left >= 0
        ? Money.format(left, symbol: symbol)
        : 'Over by ${Money.format(-left, symbol: symbol)}';

    return Card(
      elevation: 0,
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              left >= 0 ? 'Safe to spend today' : "Today's limit",
              style: theme.textTheme.titleMedium?.copyWith(color: foreground),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                headline,
                style: theme.textTheme.displayMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: daily.usedFraction,
                minHeight: 10,
                backgroundColor: foreground.withValues(alpha: 0.15),
                color: foreground,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spent today ${Money.format(daily.spentToday, symbol: symbol)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
                Text(
                  'Allowance ${Money.format(daily.allowanceToday, symbol: symbol)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: foreground.withValues(alpha: 0.2), height: 1),
            const SizedBox(height: 12),
            Text(
              daily.remainingPool >= 0
                  ? '${Money.format(daily.remainingPool, symbol: symbol)} left in your everyday budget for ${plural(daily.daysLeft, 'day')}.'
                  : 'You are ${Money.format(-daily.remainingPool, symbol: symbol)} over your everyday budget this month.',
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
