import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../logic/dashboard_controller.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/dashboard/category_progress_list.dart';
import '../widgets/dashboard/expense_tile.dart';
import '../widgets/dashboard/flags_section.dart';
import '../widgets/dashboard/month_overview_card.dart';
import '../widgets/dashboard/safe_to_spend_card.dart';
import '../widgets/expense_sheet.dart';
import 'budget_setup_screen.dart';
import 'expenses_screen.dart';

enum _MenuAction { editBudget, allExpenses, signOut }

/// The main screen: today's safe-to-spend number, the month at a glance, red
/// and green flags, category progress and recent expenses.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.auth,
    required this.user,
    required this.data,
    this.onOpenVoice,
  });

  final AuthService auth;
  final AuthUser user;
  final UserData data;

  /// Opens the voice input screen. When given, a microphone button is shown.
  final VoidCallback? onOpenVoice;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  late DashboardController _controller = _createController();
  bool _copying = false;

  DashboardController _createController() {
    return DashboardController(widget.data, DateKeys.ofMonth(DateTime.now()));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// When the app comes back after midnight on the last day of a month, start
  /// showing the new month.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_controller.monthKey == DateKeys.ofMonth(DateTime.now())) return;
    final old = _controller;
    setState(() => _controller = _createController());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _addExpense() {
    final c = _controller;
    if (c.categories.isEmpty) {
      _message('Your categories are still being set up. Try again in a moment.');
      return;
    }
    showExpenseSheet(context, data: widget.data, categories: c.categories, symbol: c.symbol);
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
          monthKey: c.monthKey,
          categories: c.categories,
          symbol: c.symbol,
          initial: c.budget,
        ),
      ),
    );
  }

  void _openAllExpenses() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpensesScreen(controller: _controller, data: widget.data),
      ),
    );
  }

  Future<void> _copyLastMonth() async {
    final c = _controller;
    setState(() => _copying = true);
    try {
      final copied = await widget.data.budgets
          .copyFromMonth(
            fromMonthKey: DateKeys.previousMonth(c.monthKey),
            toMonthKey: c.monthKey,
          )
          // Offline, the save is kept on the device and confirmed later.
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (copied == null && mounted && c.budget == null) {
        _message('There is no budget from last month to copy. Set one up instead.');
      }
    } catch (_) {
      if (mounted) _message('Could not copy last month. Check your connection.');
    } finally {
      if (mounted) setState(() => _copying = false);
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
                    case _MenuAction.editBudget:
                      _openBudgetSetup();
                    case _MenuAction.allExpenses:
                      _openAllExpenses();
                    case _MenuAction.signOut:
                      unawaited(_signOut());
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _MenuAction.editBudget, child: Text('Edit budget')),
                  PopupMenuItem(value: _MenuAction.allExpenses, child: Text('All expenses')),
                  PopupMenuItem(value: _MenuAction.signOut, child: Text('Sign out')),
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
                      onPressed: _addExpense,
                      icon: const Icon(Icons.add),
                      label: const Text('Add expense'),
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
    final recent = c.expenses.take(8).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text(
          'Hi, $name',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          monthTitle(c.monthKey),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (c.error != null) ...[
          _ErrorBanner(error: c.error!),
          const SizedBox(height: 16),
        ],
        if (budget == null || daily == null)
          _SetupCard(
            monthName: monthName(DateTime.now().month),
            copying: _copying,
            onSetup: _openBudgetSetup,
            onCopy: _copyLastMonth,
          )
        else ...[
          SafeToSpendCard(daily: daily, symbol: c.symbol),
          const SizedBox(height: 16),
          MonthOverviewCard(budget: budget, stats: c.stats, symbol: c.symbol),
          const _SectionHeader('Flags'),
          FlagsSection(controller: c),
          const _SectionHeader('Budget progress'),
          CategoryProgressList(controller: c),
        ],
        _SectionHeader(
          'Recent expenses',
          trailing: recent.isEmpty
              ? null
              : TextButton(onPressed: _openAllExpenses, child: const Text('See all')),
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No expenses yet this month. Tap Add expense to log your first one.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final expense in recent)
            ExpenseTile(
              expense: expense,
              categoryById: c.categoryById,
              symbol: c.symbol,
              data: widget.data,
              onTap: () => _editExpense(expense),
            ),
      ],
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
    required this.monthName,
    required this.copying,
    required this.onSetup,
    required this.onCopy,
  });

  final String monthName;
  final bool copying;
  final VoidCallback onSetup;
  final VoidCallback onCopy;

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
              'Set up your $monthName budget',
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your income, fixed bills and a limit for each category. '
              'Then you will see how much you can safely spend every day.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: copying ? null : onSetup, child: const Text('Set up budget')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: copying ? null : onCopy,
              child: copying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Copy last month'),
            ),
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
