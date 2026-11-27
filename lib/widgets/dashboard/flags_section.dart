import 'package:flutter/material.dart';

import '../../logic/budget_calculator.dart';
import '../../logic/dashboard_controller.dart';
import '../../models/budget_period.dart';
import '../../models/money.dart';
import '../../utils/category_icons.dart';
import '../../utils/formatters.dart';

/// Red flags (where spending is running ahead) and green flags (where the
/// user is saving), each with a one-line reason.
class FlagsSection extends StatelessWidget {
  const FlagsSection({super.key, required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final red = controller.redFlags;
    final green = controller.greenFlags;
    final now = DateTime.now();
    final symbol = controller.symbol;
    final period = controller.budget?.period;
    final early = period != null &&
        period.dayNumber(now) < BudgetCalculator.paceStartDay(period.totalDays);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlagCard(
          title: 'Red flags',
          subtitle: 'Where you are spending more',
          color: StatusColors.red(context),
          icon: Icons.flag,
          emptyText: early
              ? 'Pace flags appear a few days into the budget.'
              : 'Nothing is running ahead of budget. Nice.',
          items: [
            for (final row in red)
              _FlagItem(
                icon: iconForKey(row.line.iconKey),
                name: row.line.name,
                detail: _redDetail(row, now, symbol, period),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _FlagCard(
          title: 'Green flags',
          subtitle: 'Where you are saving',
          color: StatusColors.green(context),
          icon: Icons.flag,
          emptyText: early
              ? 'Pace flags appear a few days into the budget.'
              : 'No category is clearly under budget yet.',
          items: [
            for (final row in green)
              _FlagItem(
                icon: iconForKey(row.line.iconKey),
                name: row.line.name,
                detail: _greenDetail(row, now, symbol, period),
              ),
          ],
        ),
      ],
    );
  }

  String _redDetail(CategoryRow row, DateTime now, String symbol, BudgetPeriod? period) {
    if (row.spent > row.line.limit) {
      return 'Over budget by ${Money.format(row.spent - row.line.limit, symbol: symbol)}';
    }
    final expected = BudgetCalculator.expectedSpend(row.line, now, period: period);
    return '${Money.format(row.spent, symbol: symbol)} spent, about ${Money.format(expected, symbol: symbol)} expected by now';
  }

  String _greenDetail(CategoryRow row, DateTime now, String symbol, BudgetPeriod? period) {
    final expected = BudgetCalculator.expectedSpend(row.line, now, period: period);
    return '${Money.format(row.spent, symbol: symbol)} spent, about ${Money.format(expected, symbol: symbol)} expected by now';
  }
}

class _FlagItem {
  const _FlagItem({required this.icon, required this.name, required this.detail});

  final IconData icon;
  final String name;
  final String detail;
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.emptyText,
    required this.items,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final String emptyText;
  final List<_FlagItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(emptyText, style: theme.textTheme.bodyMedium)
            else
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.icon, size: 20, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(item.detail, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
