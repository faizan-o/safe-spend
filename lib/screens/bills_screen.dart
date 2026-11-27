import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../logic/dashboard_controller.dart';
import '../logic/dues.dart';
import '../models/recurring.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/bill_sheets.dart';
import '../widgets/debt_sheets.dart';
import '../widgets/form_bits.dart';
import 'debts_screen.dart';

/// Everything with a due date: bills, rent, fees, expected income and debts.
/// Overdue first, then due soon, then later. Paused bills are at the bottom.
class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key, required this.controller, required this.data});

  final DashboardController controller;
  final UserData data;

  /// Opens the right sheet or page for a line in the list.
  static void openDue(BuildContext context, DashboardController controller, UserData data, DueItem item) {
    final recurring = item.recurring;
    if (recurring != null) {
      showMarkPaidSheet(context, data: data, item: recurring, symbol: controller.symbol);
      return;
    }
    final debt = item.debt;
    if (debt != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DebtDetailScreen(controller: controller, data: data, debtId: debt.id),
        ),
      );
    }
  }

  void _edit(BuildContext context, RecurringItem item) {
    showRecurringSheet(
      context,
      data: data,
      categories: controller.categories,
      symbol: controller.symbol,
      existing: item,
    );
  }

  void _add(BuildContext context, {RecurringType type = RecurringType.expense}) {
    showRecurringSheet(
      context,
      data: data,
      categories: controller.categories,
      symbol: controller.symbol,
      type: type,
    );
  }

  void _addMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Bill, rent or fee'),
              subtitle: const Text('Something you have to pay on a date'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _add(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.south_west),
              title: const Text('Expected income'),
              subtitle: const Text('A salary or other money due to you'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _add(context, type: RecurringType.income);
              },
            ),
            ListTile(
              leading: const Icon(Icons.handshake_outlined),
              title: const Text('Debt or loan'),
              subtitle: const Text('Money you owe or are owed'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showDebtSheet(context, data: data, symbol: controller.symbol);
              },
            ),
          ],
        ),
      ),
    );
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
        final dues = controller.dues;
        final paused = [for (final item in controller.recurring) if (!item.active) item];

        final overdue = [for (final d in dues) if (d.overdue) d];
        final soon = [for (final d in dues) if (!d.overdue && d.daysUntil <= 7) d];
        final later = [for (final d in dues) if (d.daysUntil > 7) d];

        var toPay = 0;
        for (final d in overdue) {
          if (!d.isMoneyIn) toPay += d.amount;
        }
        var toPayWeek = 0;
        for (final d in soon) {
          if (!d.isMoneyIn) toPayWeek += d.amount;
        }

        Widget header(String text, {Color? color}) => Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
            );

        Widget dueTile(DueItem item) => _DueTile(
              item: item,
              symbol: symbol,
              onTap: () => openDue(context, controller, data, item),
              onEdit: item.recurring == null ? null : () => _edit(context, item.recurring!),
            );

        final empty = dues.isEmpty && paused.isEmpty;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Bills and due dates'),
            actions: [
              IconButton(
                tooltip: 'Debts and loans',
                icon: const Icon(Icons.handshake_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DebtsScreen(controller: controller, data: data),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'bill-fab',
            onPressed: () => _addMenu(context),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
          body: controller.loading
              ? const Center(child: CircularProgressIndicator())
              : empty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_outlined, size: 56, color: scheme.primary),
                            const SizedBox(height: 16),
                            Text('Nothing due', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                              'Add rent, bills and fees with a due date. SafeSpend shows what is coming and what is late.',
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
                        if (toPay > 0 || toPayWeek > 0)
                          Card(
                            elevation: 0,
                            color: toPay > 0 ? scheme.errorContainer : scheme.surfaceContainerHighest,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (toPay > 0)
                                    Text(
                                      '${formatMoney(toPay, symbol)} overdue',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: scheme.onErrorContainer,
                                      ),
                                    ),
                                  if (toPayWeek > 0)
                                    Text(
                                      '${formatMoney(toPayWeek, symbol)} to pay in the next 7 days',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: toPay > 0 ? scheme.onErrorContainer : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (overdue.isNotEmpty) header('Overdue', color: scheme.error),
                        for (final d in overdue) dueTile(d),
                        if (soon.isNotEmpty) header('Next 7 days'),
                        for (final d in soon) dueTile(d),
                        if (later.isNotEmpty) header('Later'),
                        for (final d in later) dueTile(d),
                        if (paused.isNotEmpty) header('Paused or finished'),
                        for (final item in paused)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.pause_circle_outline),
                            title: Text(item.title),
                            subtitle: Text('${formatMoney(item.amount, symbol)} · ${item.frequency.label}'),
                            onTap: () => _edit(context, item),
                          ),
                      ],
                    ),
        );
      },
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({required this.item, required this.symbol, required this.onTap, this.onEdit});

  final DueItem item;
  final String symbol;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  String get _kindText {
    switch (item.kind) {
      case DueKind.bill:
        final r = item.recurring;
        return r == null ? 'Bill' : (r.frequency == Frequency.once ? 'One time' : r.frequency.label);
      case DueKind.income:
        return 'Expected income';
      case DueKind.debtToPay:
        return 'Debt';
      case DueKind.loanToCollect:
        return 'Loan to collect';
    }
  }

  IconData get _icon {
    switch (item.kind) {
      case DueKind.bill:
        return Icons.receipt_long_outlined;
      case DueKind.income:
        return Icons.south_west;
      case DueKind.debtToPay:
        return Icons.north_east;
      case DueKind.loanToCollect:
        return Icons.handshake_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overdue = item.overdue;
    final soon = !overdue && item.recurring != null && item.recurring!.isDueSoon(DateTime.now());
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 8),
      color: overdue ? scheme.errorContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Icon(_icon, color: item.isMoneyIn ? StatusColors.green(context) : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      '${dueText(item.daysUntil)} · ${shortDate(item.due)} · $_kindText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: overdue ? scheme.error : (soon ? scheme.primary : scheme.onSurfaceVariant),
                        fontWeight: overdue || soon ? FontWeight.w700 : null,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${item.isMoneyIn ? '+' : ''}${formatMoney(item.amount, symbol)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: item.isMoneyIn ? StatusColors.green(context) : null,
                ),
              ),
              if (onEdit != null)
                IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: onEdit)
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
