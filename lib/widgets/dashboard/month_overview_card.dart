import 'package:flutter/material.dart';

import '../../models/money.dart';
import '../../models/month_stats.dart';
import '../../models/monthly_budget.dart';
import '../../utils/formatters.dart';

/// Where the budget's money goes: income, fixed bills, savings goal and the
/// everyday budget, with how much of the everyday budget is used.
class MonthOverviewCard extends StatelessWidget {
  const MonthOverviewCard({
    super.key,
    required this.budget,
    required this.stats,
    required this.symbol,
  });

  final MonthlyBudget budget;
  final MonthStats stats;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pool = budget.flexiblePool;
    final used = pool <= 0 ? (stats.flexibleSpent > 0 ? 1.0 : 0.0) : (stats.flexibleSpent / pool);
    final over = stats.flexibleSpent > pool;

    String money(int minor) => Money.format(minor, symbol: symbol);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${budgetName(budget)} · ${periodLabel(budget.startDate, budget.endDate)}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _Line(label: 'Money to budget', value: money(budget.income)),
            _Line(label: 'Fixed bills', value: '- ${money(budget.totalFixed)}'),
            _Line(label: 'Savings goal', value: '- ${money(budget.savingsGoal)}'),
            const Divider(height: 24),
            _Line(label: 'Everyday budget', value: money(pool), bold: true),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: used.clamp(0.0, 1.0).toDouble(),
                minHeight: 10,
                color: over ? scheme.error : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${money(stats.flexibleSpent)} spent',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  over
                      ? '${money(stats.flexibleSpent - pool)} over'
                      : '${money(pool - stats.flexibleSpent)} left',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? scheme.error : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
