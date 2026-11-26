import 'package:flutter/material.dart';

import '../../logic/dashboard_controller.dart';
import '../../models/category.dart';
import '../../models/money.dart';
import '../../models/month_summary.dart' show FlagType;
import '../../utils/category_icons.dart';
import '../../utils/formatters.dart';

/// Budget progress for every category, grouped into everyday spending, fixed
/// bills and savings. Everyday categories carry their red or green flag.
class CategoryProgressList extends StatelessWidget {
  const CategoryProgressList({super.key, required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = controller.symbol;
    final unbudgeted = controller.unbudgetedSpent;

    final groups = <(String, CategoryKind)>[
      ('Everyday spending', CategoryKind.flexible),
      ('Fixed bills', CategoryKind.fixed),
      ('Savings', CategoryKind.savings),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, kind) in groups)
          if (controller.rowsOfKind(kind).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final row in controller.rowsOfKind(kind))
              _CategoryRowTile(row: row, symbol: symbol),
          ],
        if (unbudgeted > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${Money.format(unbudgeted, symbol: symbol)} was spent in categories that are not in this month\'s budget.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryRowTile extends StatelessWidget {
  const _CategoryRowTile({required this.row, required this.symbol});

  final CategoryRow row;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categoryColor = Color(row.line.colorValue);
    final over = row.line.kind == CategoryKind.flexible && row.spent > row.line.limit;
    final barColor = over ? scheme.error : categoryColor;

    Widget? flagIcon;
    if (row.flag == FlagType.red) {
      flagIcon = Icon(Icons.flag, size: 18, color: StatusColors.red(context));
    } else if (row.flag == FlagType.green) {
      flagIcon = Icon(Icons.flag, size: 18, color: StatusColors.green(context));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: categoryColor.withValues(alpha: 0.15),
            child: Icon(iconForKey(row.line.iconKey), size: 20, color: categoryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.line.name,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (flagIcon != null) ...[flagIcon, const SizedBox(width: 6)],
                    Text(
                      '${Money.format(row.spent, symbol: symbol)} / ${Money.format(row.line.limit, symbol: symbol)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: row.usedRatio.clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                    color: barColor,
                    backgroundColor: barColor.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
