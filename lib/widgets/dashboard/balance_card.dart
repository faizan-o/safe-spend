import 'package:flutter/material.dart';

import '../../logic/balance_calculator.dart';
import '../../utils/formatters.dart';

/// The user's money right now: the opening balance plus income, minus
/// spending, with debts and loans taken into account. Before an opening
/// balance is set it asks for one.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.balance,
    required this.symbol,
    required this.owed,
    required this.lent,
    required this.onSetOpening,
    required this.onAddIncome,
  });

  /// Null until the user has entered an opening balance.
  final BalanceSummary? balance;
  final String symbol;

  /// What the user still owes, and what others still owe the user.
  final int owed;
  final int lent;
  final VoidCallback onSetOpening;
  final VoidCallback onAddIncome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = balance;

    if (summary == null) {
      return Card(
        elevation: 0,
        color: scheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 10),
                  Text(
                    'Start with your balance',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the money you have now. SafeSpend adds your income and takes off your spending '
                'from there, and you can make budgets against it.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onSetOpening, child: const Text('Set opening balance')),
            ],
          ),
        ),
      );
    }

    final negative = summary.balance < 0;
    final green = StatusColors.green(context);

    Widget stat(String label, String value, {Color? color}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
        ],
      );
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your balance', style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoney(summary.balance, symbol),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: negative ? scheme.error : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                stat('Opening (${shortDate(summary.since)})', formatMoney(summary.opening, symbol)),
                stat('Income', '+ ${formatMoney(summary.income, symbol)}', color: green),
                stat('Spent', '- ${formatMoney(summary.spent, symbol)}'),
                if (summary.loanEffect != 0)
                  stat(
                    'Loans and debts',
                    '${summary.loanEffect > 0 ? '+' : '-'} ${formatMoney(summary.loanEffect.abs(), symbol)}',
                  ),
              ],
            ),
            if (owed > 0 || lent > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (owed > 0)
                    Chip(
                      avatar: Icon(Icons.north_east, size: 16, color: scheme.error),
                      label: Text('You owe ${formatMoney(owed, symbol)}'),
                    ),
                  if (lent > 0)
                    Chip(
                      avatar: Icon(Icons.south_west, size: 16, color: green),
                      label: Text('Owed to you ${formatMoney(lent, symbol)}'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onAddIncome,
                  icon: const Icon(Icons.add),
                  label: const Text('Add income'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onSetOpening,
                  child: const Text('Opening balance'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
