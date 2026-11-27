import 'package:flutter/material.dart';

import '../../logic/dues.dart';
import '../../utils/formatters.dart';

/// The next bills, expected income and debts with a due date. Overdue ones
/// come first and are marked in red. Tapping one opens it.
class UpcomingDuesCard extends StatelessWidget {
  const UpcomingDuesCard({
    super.key,
    required this.dues,
    required this.symbol,
    required this.onTap,
    required this.onSeeAll,
    this.maxItems = 4,
  });

  final List<DueItem> dues;
  final String symbol;
  final ValueChanged<DueItem> onTap;
  final VoidCallback onSeeAll;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = dues.take(maxItems).toList();
    final overdueCount = dues.where((d) => d.overdue).length;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    overdueCount > 0 ? '$overdueCount overdue' : 'Coming up',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: overdueCount > 0 ? scheme.error : null,
                    ),
                  ),
                ),
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
            for (final item in shown) _DueRow(item: item, symbol: symbol, onTap: () => onTap(item)),
            if (dues.length > shown.length)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                child: Text(
                  '+ ${dues.length - shown.length} more',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.item, required this.symbol, required this.onTap});

  final DueItem item;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = item.overdue
        ? scheme.error
        : item.isMoneyIn
            ? StatusColors.green(context)
            : scheme.primary;
    final icon = switch (item.kind) {
      DueKind.bill => Icons.receipt_long_outlined,
      DueKind.income => Icons.south_west,
      DueKind.debtToPay => Icons.north_east,
      DueKind.loanToCollect => Icons.handshake_outlined,
    };
    final kindText = switch (item.kind) {
      DueKind.bill => '',
      DueKind.income => 'Income · ',
      DueKind.debtToPay => 'You owe · ',
      DueKind.loanToCollect => 'Owed to you · ',
    };
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.only(right: 8),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$kindText${dueText(item.daysUntil)} · ${shortDate(item.due)}',
        style: TextStyle(color: item.overdue ? scheme.error : null),
      ),
      trailing: Text(
        formatMoney(item.amount, symbol),
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
