import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/money.dart';
import '../models/monthly_budget.dart';
import '../utils/category_icons.dart';
import '../utils/formatters.dart';

/// Where the user declares the month's budget: income, fixed bills, a savings
/// goal and a limit for each everyday category.
class BudgetSetupScreen extends StatefulWidget {
  const BudgetSetupScreen({
    super.key,
    required this.data,
    required this.monthKey,
    required this.categories,
    required this.symbol,
    this.initial,
  });

  final UserData data;
  final String monthKey;
  final List<ExpenseCategory> categories;
  final String symbol;

  /// The existing budget when editing, or null for a new month.
  final MonthlyBudget? initial;

  @override
  State<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends State<BudgetSetupScreen> {
  late final TextEditingController _income = TextEditingController(
    text: (widget.initial?.income ?? 0) > 0 ? amountForField(widget.initial!.income) : '',
  );
  late final Map<String, TextEditingController> _limits = {
    for (final category in widget.categories)
      category.id: TextEditingController(text: _initialLimit(category.id)),
  };

  String? _incomeError;

  String _initialLimit(String categoryId) {
    final limit = widget.initial?.forCategory(categoryId)?.limit ?? 0;
    return limit > 0 ? amountForField(limit) : '';
  }

  @override
  void dispose() {
    _income.dispose();
    for (final controller in _limits.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int _amountOf(TextEditingController controller) => Money.parse(controller.text) ?? 0;

  int _sumOf(CategoryKind kind) {
    var total = 0;
    for (final category in widget.categories) {
      if (category.kind == kind) total += _amountOf(_limits[category.id]!);
    }
    return total;
  }

  void _save() {
    final income = _amountOf(_income);
    if (income <= 0) {
      setState(() => _incomeError = 'Enter your income for the month');
      return;
    }
    final pool = income - _sumOf(CategoryKind.fixed) - _sumOf(CategoryKind.savings);
    if (pool < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixed bills and savings are more than your income.')),
      );
      return;
    }

    final lines = <CategoryBudget>[
      for (final category in widget.categories)
        if (_amountOf(_limits[category.id]!) > 0)
          CategoryBudget.fromCategory(category, _amountOf(_limits[category.id]!)),
    ];

    // Keep lines for categories that were archived after the budget was made.
    final known = widget.categories.map((c) => c.id).toSet();
    final carried = widget.initial?.categories.where((line) => !known.contains(line.categoryId)) ??
        const <CategoryBudget>[];

    final budget = MonthlyBudget(
      monthKey: widget.monthKey,
      income: income,
      categories: [...lines, ...carried],
    );

    // Saved on the device at once and confirmed by the server later, so close
    // the screen now instead of waiting (the device may be offline).
    final messenger = ScaffoldMessenger.of(context);
    widget.data.budgets.saveBudget(budget).then((_) {}, onError: (Object error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save the budget. Check your connection.')),
      );
    });
    widget.data.profile.markOnboardingComplete().then((_) {}, onError: (Object _) {});
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = widget.symbol;

    final income = _amountOf(_income);
    final pool = income - _sumOf(CategoryKind.fixed) - _sumOf(CategoryKind.savings);
    final unassigned = pool - _sumOf(CategoryKind.flexible);
    final perDay = pool > 0 ? pool ~/ DateKeys.daysInMonth(widget.monthKey) : 0;

    String money(int minor) => Money.format(minor, symbol: symbol);

    return Scaffold(
      appBar: AppBar(title: Text('Budget for ${monthTitle(widget.monthKey)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _MoneyField(
            controller: _income,
            label: 'Income this month',
            symbol: symbol,
            icon: Icons.payments_outlined,
            errorText: _incomeError,
            onChanged: (_) => setState(() => _incomeError = null),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: pool < 0 ? scheme.errorContainer : scheme.primaryContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Everyday budget', style: theme.textTheme.labelLarge),
                  Text(
                    money(pool),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pool < 0
                        ? 'Fixed bills and savings are more than your income.'
                        : 'Income minus fixed bills and savings. About ${money(perDay)} a day.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    unassigned >= 0
                        ? '${money(unassigned)} not yet given to a category'
                        : '${money(-unassigned)} more than your everyday budget is given to categories',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: unassigned < 0 ? scheme.error : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _section(context, 'Fixed bills', 'Set aside first: rent, bills, committee.', CategoryKind.fixed),
          _section(context, 'Savings goal', 'What you want to keep this month.', CategoryKind.savings),
          _section(context, 'Everyday spending', 'A limit for each kind of daily spending.', CategoryKind.flexible),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(onPressed: _save, child: const Text('Save budget')),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String hint, CategoryKind kind) {
    final theme = Theme.of(context);
    final items = widget.categories.where((c) => c.kind == kind).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final category in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MoneyField(
              controller: _limits[category.id]!,
              label: category.name,
              symbol: widget.symbol,
              icon: iconForKey(category.iconKey),
              iconColor: Color(category.colorValue),
              onChanged: (_) => setState(() {}),
            ),
          ),
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.symbol,
    required this.icon,
    required this.onChanged,
    this.iconColor,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String symbol;
  final IconData icon;
  final Color? iconColor;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      textInputAction: TextInputAction.next,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: iconColor),
        prefixText: '$symbol ',
        errorText: errorText,
      ),
    );
  }
}
