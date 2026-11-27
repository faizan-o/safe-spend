import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../logic/balance_calculator.dart';
import '../logic/dashboard_controller.dart';
import '../models/debt.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/debt_sheets.dart';
import '../widgets/form_bits.dart';

/// Money I owe and money I am owed. Tap one to see repayments.
class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key, required this.controller, required this.data});

  final DashboardController controller;
  final UserData data;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final symbol = controller.symbol;
        final today = DateTime.now();
        final debts = controller.debts;
        final owe = [for (final d in debts) if (!d.isOwedToMe && !d.isSettled) d];
        final owed = [for (final d in debts) if (d.isOwedToMe && !d.isSettled) d];
        final settled = [for (final d in debts) if (d.isSettled) d];
        final totalOwed = BalanceCalculator.totalOwed(controller.debts);
        final totalLent = BalanceCalculator.totalLent(controller.debts);

        Widget header(String text) => Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            );

        Widget tile(Debt debt) => _DebtTile(
              debt: debt,
              symbol: symbol,
              today: today,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DebtDetailScreen(controller: controller, data: data, debtId: debt.id),
                ),
              ),
            );

        return Scaffold(
          appBar: AppBar(title: const Text('Debts and loans')),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'debt-fab',
            onPressed: () => showDebtSheet(context, data: data, symbol: symbol),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
          body: controller.loading
              ? const Center(child: CircularProgressIndicator())
              : debts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.handshake_outlined, size: 56, color: scheme.primary),
                            const SizedBox(height: 16),
                            Text('No debts or loans', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                              'Track money you owe and money you lent, with due dates and repayments.',
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
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryBox(
                                label: 'You owe',
                                value: formatMoney(totalOwed, symbol),
                                color: scheme.error,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryBox(
                                label: 'Owed to you',
                                value: formatMoney(totalLent, symbol),
                                color: StatusColors.green(context),
                              ),
                            ),
                          ],
                        ),
                        if (owe.isNotEmpty) header('I owe'),
                        for (final debt in owe) tile(debt),
                        if (owed.isNotEmpty) header('Owed to me'),
                        for (final debt in owed) tile(debt),
                        if (settled.isNotEmpty) header('Settled'),
                        for (final debt in settled) tile(debt),
                      ],
                    ),
        );
      },
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt, required this.symbol, required this.today, required this.onTap});

  final Debt debt;
  final String symbol;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overdue = debt.isOverdue(today);
    final days = debt.daysUntilDue(today);
    final String status;
    if (debt.isSettled) {
      status = debt.isOwedToMe ? 'Paid back' : 'Paid off';
    } else if (days == null) {
      status = 'No due date';
    } else {
      status = dueText(days);
    }
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 8),
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(debt.isOwedToMe ? Icons.south_west : Icons.north_east,
                      color: debt.isOwedToMe ? StatusColors.green(context) : scheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(debt.person, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          status,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: overdue ? scheme.error : scheme.onSurfaceVariant,
                            fontWeight: overdue ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatMoney(debt.isSettled ? debt.amount : debt.remaining, symbol),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (!debt.isSettled && debt.paid > 0)
                        Text(
                          'of ${formatMoney(debt.amount, symbol)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
              if (debt.paid > 0 && !debt.isSettled) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: debt.progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One debt with its repayments.
class DebtDetailScreen extends StatelessWidget {
  const DebtDetailScreen({super.key, required this.controller, required this.data, required this.debtId});

  final DashboardController controller;
  final UserData data;
  final String debtId;

  Debt? _find() {
    for (final debt in controller.debts) {
      if (debt.id == debtId) return debt;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final debt = _find();
        if (debt == null) {
          // Deleted (here or on another device).
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This entry no longer exists.')),
          );
        }
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final symbol = controller.symbol;
        final today = DateTime.now();
        final lent = debt.isOwedToMe;
        final payments = [...debt.payments]..sort((a, b) => b.date.compareTo(a.date));
        final days = debt.daysUntilDue(today);

        void markSettled() {
          final messenger = ScaffoldMessenger.of(context);
          data.debts
              .addPayment(debt, DebtPayment(id: '', amount: debt.remaining, date: DateTime.now()))
              .then((_) {}, onError: (Object _) => reportSaveError(messenger, 'the repayment'));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(debt.person),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final changed = await showDebtSheet(context, data: data, symbol: symbol, existing: debt);
                  // Deleted from the sheet: leave this page too.
                  if (changed == true && context.mounted && _find() == null) Navigator.of(context).maybePop();
                },
              ),
            ],
          ),
          floatingActionButton: debt.isSettled
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'repay-fab',
                  onPressed: () => showRepaymentSheet(context, data: data, debt: debt, symbol: symbol),
                  icon: const Icon(Icons.add),
                  label: Text(lent ? 'Money received' : 'Add repayment'),
                ),
          body: ListView(
            padding: Responsive.listPadding(context, maxWidth: 720, top: 8, bottom: 96),
            children: [
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lent ? 'Owes you' : 'You owe',
                        style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(debt.remaining, symbol),
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: debt.progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                      const SizedBox(height: 8),
                      Text(
                        '${formatMoney(debt.paid, symbol)} of ${formatMoney(debt.amount, symbol)} '
                        '${lent ? 'received back' : 'repaid'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${lent ? 'Lent' : 'Borrowed'} on ${shortDate(debt.date)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (days != null && !debt.isSettled)
                        Text(
                          '${dueText(days)} · ${shortDate(debt.due!)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: days < 0 ? scheme.error : null,
                            fontWeight: days < 0 ? FontWeight.w700 : null,
                          ),
                        ),
                      if (debt.note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(debt.note, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                      if (!debt.isSettled) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: markSettled,
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(lent ? 'Mark fully paid back' : 'Mark fully paid'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 4),
                child: Text('Repayments', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nothing repaid yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final payment in payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(formatMoney(payment.amount, symbol)),
                  subtitle: Text(
                    payment.note.isEmpty ? shortDate(payment.date) : '${shortDate(payment.date)} · ${payment.note}',
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => showRepaymentSheet(
                    context,
                    data: data,
                    debt: debt,
                    symbol: symbol,
                    payment: payment,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
