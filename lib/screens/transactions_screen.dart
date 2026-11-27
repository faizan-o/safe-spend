import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../logic/activity.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/dashboard/expense_tile.dart';
import '../widgets/dashboard/income_tile.dart';
import '../widgets/expense_sheet.dart';
import '../widgets/income_sheet.dart';

enum _Filter { all, expenses, income }

/// Every expense and income of any month, grouped by day. Go back month by
/// month to find an old entry; tap one to correct anything about it (amount,
/// category, date, time, notes), swipe to delete.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    required this.data,
    required this.categories,
    required this.symbol,
  });

  final UserData data;
  final List<ExpenseCategory> categories;
  final String symbol;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late final String _currentMonth = DateKeys.ofMonth(DateTime.now());
  late String _monthKey = _currentMonth;
  _Filter _filter = _Filter.all;

  List<Expense> _expenses = const [];
  List<Income> _incomes = const [];
  bool _expensesLoaded = false;
  bool _incomesLoaded = false;
  Object? _error;
  StreamSubscription<List<Expense>>? _expenseSub;
  StreamSubscription<List<Income>>? _incomeSub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _expenseSub?.cancel();
    _incomeSub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _expenseSub?.cancel();
    _incomeSub?.cancel();
    _expensesLoaded = false;
    _incomesLoaded = false;
    _error = null;
    _expenseSub = widget.data.expenses.watchMonth(_monthKey).listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _expenses = value;
          _expensesLoaded = true;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _expensesLoaded = true;
        });
      },
    );
    _incomeSub = widget.data.incomes.watchMonth(_monthKey).listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _incomes = value;
          _incomesLoaded = true;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _incomesLoaded = true;
        });
      },
    );
  }

  bool get _canGoNext => _monthKey.compareTo(_currentMonth) < 0;

  void _go(bool forward) {
    setState(() {
      _monthKey = forward ? DateKeys.nextMonth(_monthKey) : DateKeys.previousMonth(_monthKey);
    });
    _subscribe();
  }

  void _addExpense() {
    showExpenseSheet(context, data: widget.data, categories: widget.categories, symbol: widget.symbol);
  }

  void _addIncome() {
    showIncomeSheet(context, data: widget.data, symbol: widget.symbol);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = widget.symbol;
    final now = DateTime.now();
    final green = StatusColors.green(context);

    final expenses = _filter == _Filter.income ? const <Expense>[] : _expenses;
    final incomes = _filter == _Filter.expenses ? const <Income>[] : _incomes;
    final spentTotal = _expenses.fold<int>(0, (sum, e) => sum + e.amount);
    final incomeTotal = _incomes.fold<int>(0, (sum, i) => sum + i.amount);
    final items = ActivityItem.merge(expenses, incomes);
    final byId = {for (final c in widget.categories) c.id: c};

    // A header row is added whenever the day changes.
    final rows = <Object>[];
    String? lastDay;
    for (final item in items) {
      final dayKey = DateKeys.ofDay(item.date);
      if (dayKey != lastDay) {
        var spent = 0;
        var received = 0;
        for (final other in items) {
          if (DateKeys.ofDay(other.date) != dayKey) continue;
          if (other.isIncome) {
            received += other.income!.amount;
          } else {
            spent += other.expense!.amount;
          }
        }
        rows.add(_DayHeader(
          label: dayLabel(item.date, now),
          spent: spent,
          received: received,
          symbol: symbol,
        ));
        lastDay = dayKey;
      }
      rows.add(item);
    }

    final loading = !_expensesLoaded || !_incomesLoaded;

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'tx-income-fab',
            tooltip: 'Add income',
            onPressed: _addIncome,
            child: const Icon(Icons.south_west),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'tx-expense-fab',
            onPressed: _addExpense,
            icon: const Icon(Icons.add),
            label: const Text('Add expense'),
          ),
        ],
      ),
      body: CenteredContent(
        maxWidth: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _go(false),
                  ),
                  Expanded(
                    child: Text(
                      monthTitle(_monthKey),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _canGoNext ? () => _go(true) : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_Filter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Filter.all, label: Text('All')),
                  ButtonSegment(value: _Filter.expenses, label: Text('Expenses')),
                  ButtonSegment(value: _Filter.income, label: Text('Income')),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) => setState(() => _filter = selection.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Income + ${formatMoney(incomeTotal, symbol)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: green, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Spent - ${formatMoney(spentTotal, symbol)}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Could not load this month. Check your connection and that the Firestore rules are deployed.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                        ),
                      ),
                    )
                  : loading
                      ? const Center(child: CircularProgressIndicator())
                      : rows.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'Nothing recorded in ${monthTitle(_monthKey)}.',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                if (row is _DayHeader) return row;
                                final item = row as ActivityItem;
                                final income = item.income;
                                if (income != null) {
                                  return IncomeTile(
                                    income: income,
                                    symbol: symbol,
                                    data: widget.data,
                                    onTap: () => showIncomeSheet(
                                      context,
                                      data: widget.data,
                                      symbol: symbol,
                                      existing: income,
                                    ),
                                  );
                                }
                                final expense = item.expense!;
                                return ExpenseTile(
                                  expense: expense,
                                  categoryById: byId,
                                  symbol: symbol,
                                  data: widget.data,
                                  onTap: () => showExpenseSheet(
                                    context,
                                    data: widget.data,
                                    categories: widget.categories,
                                    symbol: symbol,
                                    existing: expense,
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.spent,
    required this.received,
    required this.symbol,
  });

  final String label;
  final int spent;
  final int received;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final parts = [
      if (received > 0) '+ ${formatMoney(received, symbol)}',
      if (spent > 0) '- ${formatMoney(spent, symbol)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(parts.join('   '), style: style),
        ],
      ),
    );
  }
}
