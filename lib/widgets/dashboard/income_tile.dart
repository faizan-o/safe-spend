import 'package:flutter/material.dart';

import '../../data/user_data.dart';
import '../../models/income.dart';
import '../../utils/formatters.dart';
import '../income_sheet.dart';

/// One income in a list. Swipe left to delete (with undo); tap to edit.
class IncomeTile extends StatelessWidget {
  const IncomeTile({
    super.key,
    required this.income,
    required this.symbol,
    required this.data,
    required this.onTap,
  });

  final Income income;
  final String symbol;
  final UserData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final green = StatusColors.green(context);

    final details = [
      income.source,
      dayLabel(income.date, DateTime.now()),
      if (income.note.isNotEmpty) income.note,
    ].join(' · ');

    return Dismissible(
      key: ValueKey('income-${income.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => deleteIncomeWithUndo(ScaffoldMessenger.of(context), data, income, symbol),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: CircleAvatar(
          backgroundColor: green.withValues(alpha: 0.15),
          child: Icon(Icons.south_west, color: green),
        ),
        title: Text(
          '+ ${formatMoney(income.amount, symbol)}',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: green),
        ),
        subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: income.recurringId != null
            ? Icon(Icons.autorenew, size: 18, color: scheme.onSurfaceVariant)
            : null,
      ),
    );
  }
}
