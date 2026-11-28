import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../logic/balance_calculator.dart';
import '../logic/dashboard_controller.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/dashboard/balance_card.dart';
import '../widgets/dashboard/category_progress_list.dart';
import '../widgets/dashboard/expense_tile.dart';
import '../widgets/dashboard/flags_section.dart';
import '../widgets/dashboard/income_tile.dart';
import '../widgets/dashboard/month_overview_card.dart';
import '../widgets/dashboard/safe_to_spend_card.dart';
import '../widgets/dashboard/upcoming_dues_card.dart';
import '../widgets/bill_sheets.dart';
import '../widgets/debt_sheets.dart';
import '../widgets/expense_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/income_sheet.dart';
import '../widgets/opening_balance_sheet.dart';
import 'bills_screen.dart';
import 'budget_setup_screen.dart';
import 'budgets_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

enum _MenuAction { budgets, transactions, receipts, settings, signOut }

/// The main screen: the balance, today's safe-to-spend number, the budget at a
/// glance, what is due soon, red and green flags, category progress and recent
/// activity (expenses and income).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.auth,
    required this.user,
    required this.data,
    required this.controller,
    this.onOpenVoice,
    this.onOpenBills,
    this.onOpenReceipts,
  });

  final AuthService auth;
  final AuthUser user;
  final UserData data;

  /// Shared with the other tabs; owned (and disposed) by the shell.
  final DashboardController controller;

  /// Opens the voice input screen. When given, a microphone button is shown.
  final VoidCallback? onOpenVoice;

  /// Opens the Bills tab ("See all" on the coming-up card).
  final VoidCallback? onOpenBills;

  /// Opens the receipts list. Null when Receipts already has its own tab.
  final VoidCallback? onOpenReceipts;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _repeating = false;

  DashboardController get _controller => widget.controller;

  void _message(String text) => showMessage(context, text);

  void _addExpense() {
    final c = _controller;
    if (c.categories.isEmpty) {
      _message('Your categories are still being set up. Try again in a moment.');
      return;
    }
    showExpenseSheet(context, data: widget.data, categories: c.categories, symbol: c.symbol);
  }

  void _addIncome() {
    showIncomeSheet(context, data: widget.data, symbol: _controller.symbol);
  }

  void _addMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.north_east),
              title: const Text('Add expense'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addExpense();
              },
            ),
            ListTile(
              leading: const Icon(Icons.south_west),
              title: const Text('Add income'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addIncome();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Add bill or due date'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showRecurringSheet(
                  context,
                  data: widget.data,
                  categories: _controller.categories,
                  symbol: _controller.symbol,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.handshake_outlined),
              title: const Text('Add debt or loan'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showDebtSheet(context, data: widget.data, symbol: _controller.symbol);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editExpense(Expense expense) {
    final c = _controller;
    showExpenseSheet(
      context,
      data: widget.data,
      categories: c.categories,
      symbol: c.symbol,
      existing: expense,
    );
  }

  void _editIncome(Income income) {
    showIncomeSheet(context, data: widget.data, symbol: _controller.symbol, existing: income);
  }

  void _setOpeningBalance() {
    final profile = _controller.profile;
    showOpeningBalanceSheet(
      context,
      data: widget.data,
      symbol: _controller.symbol,
      currentAmount: profile?.hasOpeningBalance == true ? profile!.openingBalance : null,
      currentDay: profile?.hasOpeningBalance == true ? DateKeys.parseDay(profile!.openingBalanceDay) : null,
    );
  }

  void _openBudgetSetup() {
    final c = _controller;
    if (c.categories.isEmpty) {
      _message('Your categories are still being set up. Try again in a moment.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BudgetSetupScreen(
          data: widget.data,
          categories: c.categories,
          symbol: c.symbol,
          initial: null,
          balance: c.balance?.balance,
        ),
      ),
    );
  }

  void _editCurrentBudget() {
    final c = _controller;
    final budget = c.budget;
    if (budget == null || c.categories.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BudgetSetupScreen(
          data: widget.data,
          categories: c.categories,
          symbol: c.symbol,
          initial: budget,
          balance: c.balance?.balance,
        ),
      ),
    );
  }

  void _openBudgets() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BudgetsScreen(controller: _controller, data: widget.data),
      ),
    );
  }

  void _openTransactions() {
    final c = _controller;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionsScreen(data: widget.data, categories: c.categories, symbol: c.symbol),
      ),
    );
  }

  void _openBills() {
    final open = widget.onOpenBills;
    if (open != null) {
      open();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BillsScreen(controller: _controller, data: widget.data),
      ),
    );
  }

  Future<void> _repeatLast() async {
    setState(() => _repeating = true);
    try {
      final repeated = await widget.data.budgets
          .repeatLatest()
          // Offline, the save is kept on the device and confirmed later.
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (repeated == null && mounted && _controller.budget == null) {
        _message('There is no earlier budget to repeat. Set one up instead.');
      }
    } catch (_) {
      if (mounted) _message('Could not repeat the budget. Check your connection.');
    } finally {
      if (mounted) setState(() => _repeating = false);
    }
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text(AppConfig.appName),
            actions: [
              PopupMenuButton<_MenuAction>(
                tooltip: 'Menu',
                onSelected: (action) {
                  switch (action) {
                    case _MenuAction.budgets:
                      _openBudgets();
                    case _MenuAction.transactions:
                      _openTransactions();
                    case _MenuAction.receipts:
                      widget.onOpenReceipts?.call();
                    case _MenuAction.settings:
                      openSettings(context, widget.auth, widget.user, data: widget.data);
                    case _MenuAction.signOut:
                      unawaited(_signOut());
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: _MenuAction.budgets, child: Text('Budgets')),
                  const PopupMenuItem(value: _MenuAction.transactions, child: Text('All transactions')),
                  if (widget.onOpenReceipts != null) const PopupMenuItem(value: _MenuAction.receipts, child: Text('Receipts')),
                  const PopupMenuItem(value: _MenuAction.settings, child: Text('Settings')),
                  const PopupMenuItem(value: _MenuAction.signOut, child: Text('Sign out')),
                ],
              ),
            ],
          ),
          floatingActionButton: c.loading
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.onOpenVoice != null) ...[
                      FloatingActionButton(
                        heroTag: 'voice-fab',
                        tooltip: 'Add by voice',
                        onPressed: widget.onOpenVoice,
                        child: const Icon(Icons.mic),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FloatingActionButton.extended(
                      heroTag: 'add-fab',
                      onPressed: _addMenu,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
          body: c.loading ? const Center(child: CircularProgressIndicator()) : _content(context, c),
        );
      },
    );
  }

  Widget _content(BuildContext context, DashboardController c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final budget = c.budget;
    final daily = c.daily;
    final name = (c.profile?.name.trim().isNotEmpty ?? false)
        ? c.profile!.name.trim().split(RegExp(r'\s+')).first
        : widget.user.firstName;
    final recent = c.recentActivity;
    final active = c.activeBudgets;
    final dues = c.dues;
    final today = DateTime.now();

    final greeting = <Widget>[
      Text(
        'Hi, $name',
        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      Text(
        '${monthName(today.month)} ${today.year}',
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      if (c.error != null) ...[
        _ErrorBanner(error: c.error!),
        const SizedBox(height: 16),
      ],
      BalanceCard(
        balance: c.balance,
        symbol: c.symbol,
        owed: BalanceCalculator.totalOwed(c.debts),
        lent: BalanceCalculator.totalLent(c.debts),
        onSetOpening: _setOpeningBalance,
        onAddIncome: _addIncome,
      ),
      const SizedBox(height: 16),
    ];

    // Left: the numbers that matter most. Right: progress and recent activity.
    final summary = <Widget>[
      if (budget == null || daily == null)
        _SetupCard(
          working: _repeating,
          canRepeat: c.budgets.isNotEmpty,
          onSetup: _openBudgetSetup,
          onRepeat: _repeatLast,
        )
      else ...[
        if (active.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in active)
                ChoiceChip(
                  label: Text(budgetName(b)),
                  selected: b.id == budget.id,
                  onSelected: (_) => c.selectBudget(b.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        SafeToSpendCard(daily: daily, symbol: c.symbol),
        const SizedBox(height: 16),
        MonthOverviewCard(budget: budget, stats: c.stats, symbol: c.symbol),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _editCurrentBudget,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit this budget'),
          ),
        ),
      ],
      if (dues.isNotEmpty) ...[
        const _SectionHeader('Due dates'),
        UpcomingDuesCard(
          dues: dues,
          symbol: c.symbol,
          onTap: (item) => BillsScreen.openDue(context, c, widget.data, item),
          onSeeAll: _openBills,
        ),
      ],
      if (budget != null && daily != null) ...[
        const _SectionHeader('Flags'),
        FlagsSection(controller: c),
      ],
    ];
    final details = <Widget>[
      if (budget != null && daily != null) ...[
        const _SectionHeader('Budget progress'),
        CategoryProgressList(controller: c),
      ],
      _SectionHeader(
        'Recent activity',
        trailing: recent.isEmpty ? null : TextButton(onPressed: _openTransactions, child: const Text('See all')),
      ),
      if (recent.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Nothing yet. Tap Add to log an expense or income.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        )
      else
        for (final item in recent)
          if (item.isIncome)
            IncomeTile(
              income: item.income!,
              symbol: c.symbol,
              data: widget.data,
              onTap: () => _editIncome(item.income!),
            )
          else
            ExpenseTile(
              expense: item.expense!,
              categoryById: c.categoryById,
              symbol: c.symbol,
              data: widget.data,
              onTap: () => _editExpense(item.expense!),
            ),
    ];

    final width = MediaQuery.sizeOf(context).width;
    if (width >= Responsive.twoColumnBreakpoint) {
      // Desktop / large window: two columns, centered.
      final side = ((width - 1200) / 2).clamp(24.0, double.infinity);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(side, 16, side, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...greeting,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: summary)),
                const SizedBox(width: 32),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: details)),
              ],
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: Responsive.listPadding(context, maxWidth: 640, top: 8, bottom: 96),
      children: [...greeting, ...summary, ...details],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.working,
    required this.canRepeat,
    required this.onSetup,
    required this.onRepeat,
  });

  final bool working;
  final bool canRepeat;
  final VoidCallback onSetup;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set up a budget',
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a week, a month, a year or your own dates, and how much money to budget. '
              'Then you will see how much you can safely spend every day.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: working ? null : onSetup, child: const Text('Set up budget')),
            if (canRepeat) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: working ? null : onRepeat,
                child: working
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Repeat my last budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Some data could not be loaded. If this keeps happening, check that the "
              "Firestore rules have been deployed and that you are online.\n\n$error",
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
