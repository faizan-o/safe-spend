import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../logic/dashboard_controller.dart';
import '../models/expense.dart';
import '../models/money.dart';
import '../utils/formatters.dart';
import '../widgets/dashboard/expense_tile.dart';
import '../widgets/expense_sheet.dart';
import '../utils/responsive.dart';

/// Every expense of the month, grouped by day with a total per day.
/// Swipe to delete, tap to edit.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key, required this.controller, required this.data});

  final DashboardController controller;
  final UserData data;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final symbol = controller.symbol;
        final expenses = controller.expenses;
        final now = DateTime.now();

        // Newest first; a header row is added whenever the day changes.
        final dayTotals = <String, int>{};
        for (final expense in expenses) {
          dayTotals[expense.dayKey] = (dayTotals[expense.dayKey] ?? 0) + expense.amount;
        }
        final items = <Object>[];
        String? lastDay;
        for (final expense in expenses) {
          if (expense.dayKey != lastDay) {
            items.add(_DayHeader(
              label: dayLabel(expense.date, now),
              total: Money.format(dayTotals[expense.dayKey] ?? 0, symbol: symbol),
            ));
            lastDay = expense.dayKey;
          }
          items.add(expense);
        }

        return Scaffold(
          appBar: AppBar(title: Text('Expenses · ${monthTitle(controller.monthKey)}')),
          body: expenses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No expenses this month yet.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: Responsive.listPadding(context, maxWidth: 760),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item is _DayHeader) return item;
                    final expense = item as Expense;
                    return ExpenseTile(
                      expense: expense,
                      categoryById: controller.categoryById,
                      symbol: symbol,
                      data: data,
                      onTap: () => showExpenseSheet(
                        context,
                        data: data,
                        categories: controller.categories,
                        symbol: symbol,
                        existing: expense,
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.total});

  final String label;
  final String total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            total,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
