import 'package:flutter/material.dart';

import '../../data/user_data.dart';
import '../../models/category.dart';
import '../../models/expense.dart';
import '../../models/money.dart';
import '../../utils/category_icons.dart';
import '../../utils/formatters.dart';

/// One expense in a list. Swipe left to delete (with undo); tap to edit.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    required this.categoryById,
    required this.symbol,
    required this.data,
    required this.onTap,
  });

  final Expense expense;
  final Map<String, ExpenseCategory> categoryById;
  final String symbol;
  final UserData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = categoryById[expense.categoryId];
    final color = Color(category?.colorValue ?? 0xFF546E7A);
    final now = DateTime.now();

    final details = [
      expense.categoryName,
      dayLabel(expense.date, now),
      if (expense.note.isNotEmpty) expense.note,
    ].join(' · ');

    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => deleteExpenseWithUndo(context, data, expense, symbol),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(iconForKey(category?.iconKey ?? 'category'), color: color),
        ),
        title: Text(
          Money.format(expense.amount, symbol: symbol, showDecimals: expense.amount % 100 != 0),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: expense.source == ExpenseSource.voice
            ? Icon(Icons.mic, size: 18, color: scheme.onSurfaceVariant)
            : null,
      ),
    );
  }
}

/// Deletes an expense and offers to undo it. The delete is sent right away;
/// undo saves the same expense again.
void deleteExpenseWithUndo(
  BuildContext context,
  UserData data,
  Expense expense,
  String symbol,
) {
  final messenger = ScaffoldMessenger.of(context);

  void reportError(Object error) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not save the change. Check your connection.')),
    );
  }

  data.expenses.deleteExpense(expense).then((_) {}, onError: reportError);

  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text('Deleted ${Money.format(expense.amount, symbol: symbol)} · ${expense.categoryName}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            data.expenses
                .addExpense(Expense(
                  amount: expense.amount,
                  categoryId: expense.categoryId,
                  categoryName: expense.categoryName,
                  categoryKind: expense.categoryKind,
                  note: expense.note,
                  date: expense.date,
                  source: expense.source,
                  transcript: expense.transcript,
                ))
                .then((_) {}, onError: reportError);
          },
        ),
      ),
    );
}
