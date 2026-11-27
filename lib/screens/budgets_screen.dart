import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../logic/dashboard_controller.dart';
import '../models/budget_period.dart';
import '../models/monthly_budget.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/form_bits.dart';
import 'budget_setup_screen.dart';

/// Every budget: the ones in force now, the ones coming up and past ones.
/// Tap one to change it; create new ones for any period.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key, required this.controller, required this.data});

  final DashboardController controller;
  final UserData data;

  void _open(BuildContext context, {MonthlyBudget? initial}) {
    if (controller.categories.isEmpty) {
      showMessage(context, 'Your categories are still being set up. Try again in a moment.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BudgetSetupScreen(
          data: data,
          categories: controller.categories,
          symbol: controller.symbol,
          initial: initial,
          balance: controller.balance?.balance,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, MonthlyBudget budget) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmAction(
      context,
      title: 'Delete this budget?',
      message: '${budgetName(budget)} (${periodLabel(budget.startDate, budget.endDate)}) is removed. '
          'Your expenses are not affected.',
    );
    if (!ok) return;
    data.budgets.deleteBudget(budget.id).then((_) {}, onError: (Object _) => reportSaveError(messenger, 'the change'));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final symbol = controller.symbol;
        final today = DateTime.now();

        final current = <MonthlyBudget>[];
        final upcoming = <MonthlyBudget>[];
        final past = <MonthlyBudget>[];
        for (final budget in controller.budgets) {
          final period = budget.period;
          if (period.contains(today)) {
            current.add(budget);
          } else if (period.hasNotStarted(today)) {
            upcoming.add(budget);
          } else {
            past.add(budget);
          }
        }
        final balance = controller.balance;
        final inForce = current.fold<int>(0, (sum, b) => sum + b.income);

        Widget header(String text) => Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            );

        Widget tile(MonthlyBudget budget) => _BudgetTile(
              budget: budget,
              symbol: symbol,
              showing: controller.budget?.id == budget.id,
              onTap: () => _open(context, initial: budget),
              onDelete: () => _delete(context, budget),
            );

        return Scaffold(
          appBar: AppBar(title: const Text('Budgets')),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'budget-fab',
            onPressed: () => _open(context),
            icon: const Icon(Icons.add),
            label: const Text('New budget'),
          ),
          body: controller.budgets.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pie_chart_outline, size: 56, color: scheme.primary),
                        const SizedBox(height: 16),
                        Text('No budgets yet', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Make a budget for a week, a month, a year or any dates, against the money you have.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: Responsive.listPadding(context, maxWidth: 720, top: 8, bottom: 96),
                  children: [
                    if (balance != null && current.isNotEmpty)
                      Card(
                        elevation: 0,
                        color: scheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Budgets in force add up to ${formatMoney(inForce, symbol)}. '
                            'Your balance is ${formatMoney(balance.balance, symbol)}.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    if (current.isNotEmpty) header('In force now'),
                    for (final budget in current) tile(budget),
                    if (upcoming.isNotEmpty) header('Coming up'),
                    for (final budget in upcoming) tile(budget),
                    if (past.isNotEmpty) header('Past'),
                    for (final budget in past) tile(budget),
                  ],
                ),
        );
      },
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.budget,
    required this.symbol,
    required this.showing,
    required this.onTap,
    required this.onDelete,
  });

  final MonthlyBudget budget;
  final String symbol;
  final bool showing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final period = budget.period;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 8),
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            budgetName(budget),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (showing) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Showing', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${budget.periodType.label} · ${periodLabel(period.start, period.end)} · ${plural(period.totalDays, 'day')}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Everyday ${formatMoney(budget.flexiblePool, symbol)} · Fixed ${formatMoney(budget.totalFixed, symbol)} · Savings ${formatMoney(budget.savingsGoal, symbol)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                formatMoney(budget.income, symbol),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  if (value == 'edit') onTap();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
