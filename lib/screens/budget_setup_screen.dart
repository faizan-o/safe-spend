import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/user_data.dart';
import '../models/budget_period.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/money.dart';
import '../models/monthly_budget.dart';
import '../utils/category_icons.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/form_bits.dart';

/// Where the user sets up a budget: how long it lasts (a week, a month, a
/// year or any dates), the money to budget (it can be taken from the current
/// balance), a savings goal and a limit for each category.
class BudgetSetupScreen extends StatefulWidget {
  const BudgetSetupScreen({
    super.key,
    required this.data,
    required this.categories,
    required this.symbol,
    this.initial,
    this.balance,
  });

  final UserData data;
  final List<ExpenseCategory> categories;
  final String symbol;

  /// The existing budget when editing, or null for a new one.
  final MonthlyBudget? initial;

  /// The user's balance right now, when they have set an opening balance.
  /// The budget amount can be taken from it.
  final int? balance;

  @override
  State<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends State<BudgetSetupScreen> {
  late final TextEditingController _income = TextEditingController(
    text: (widget.initial?.income ?? 0) > 0 ? amountForField(widget.initial!.income) : '',
  );
  late final TextEditingController _title = TextEditingController(text: widget.initial?.title ?? '');
  late final Map<String, TextEditingController> _limits = {
    for (final category in widget.categories)
      category.id: TextEditingController(text: _initialLimit(category.id)),
  };

  late PeriodType _type = widget.initial?.periodType ?? PeriodType.monthly;
  late DateTime _start = widget.initial?.startDate ??
      BudgetPeriod.defaultStart(PeriodType.monthly, DateTime.now());
  late DateTime _end = widget.initial?.endDate ??
      BudgetPeriod.endFor(PeriodType.monthly, BudgetPeriod.defaultStart(PeriodType.monthly, DateTime.now()));

  String? _incomeError;
  bool _saving = false;

  bool get _editing => widget.initial != null;

  String _initialLimit(String categoryId) {
    final limit = widget.initial?.forCategory(categoryId)?.limit ?? 0;
    return limit > 0 ? amountForField(limit) : '';
  }

  @override
  void dispose() {
    _income.dispose();
    _title.dispose();
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

  /// Picks a preset length. Week, month and year line the dates up with the
  /// period that contains the current start date; custom keeps the dates.
  void _setType(PeriodType type) {
    setState(() {
      _type = type;
      if (type != PeriodType.custom) {
        _start = BudgetPeriod.defaultStart(type, _start);
        _end = BudgetPeriod.endFor(type, _start);
      }
    });
  }

  void _setStart(DateTime day) {
    setState(() {
      _start = DateKeys.startOfDay(day);
      if (_type == PeriodType.custom) {
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = BudgetPeriod.endFor(_type, _start);
      }
    });
  }

  /// Choosing an end date by hand makes the budget custom.
  void _setEnd(DateTime day) {
    setState(() {
      _end = DateKeys.startOfDay(day);
      if (_end != BudgetPeriod.endFor(_type, _start)) _type = PeriodType.custom;
    });
  }

  Future<void> _save() async {
    final income = _amountOf(_income);
    if (income <= 0) {
      setState(() => _incomeError = 'Enter the money you want to budget');
      return;
    }
    if (_end.isBefore(_start)) {
      showMessage(context, 'The end date is before the start date.');
      return;
    }
    final pool = income - _sumOf(CategoryKind.fixed) - _sumOf(CategoryKind.savings);
    if (pool < 0) {
      showMessage(context, 'Fixed bills and savings are more than the money you are budgeting.');
      return;
    }

    final balance = widget.balance;
    if (balance != null && income > balance) {
      final go = await confirmAction(
        context,
        title: 'More than your balance',
        message: 'You are budgeting ${formatMoney(income, widget.symbol)} but your balance is '
            '${formatMoney(balance, widget.symbol)}. Continue anyway? (That is fine if you expect '
            'income during this budget.)',
        confirmLabel: 'Continue',
      );
      if (!go || !mounted) return;
    }

    final period = BudgetPeriod(type: _type, start: _start, end: _end);
    final id = widget.initial?.id ?? widget.data.budgets.newIdFor(period);

    // A new calendar-month budget uses the month key as its id; do not
    // silently replace one that already exists.
    if (!_editing && period.isCalendarMonth) {
      setState(() => _saving = true);
      final existing = await widget.data.budgets.getBudget(id);
      if (!mounted) return;
      setState(() => _saving = false);
      if (existing != null) {
        final replace = await confirmAction(
          context,
          title: 'Replace this month\'s budget?',
          message: 'You already have a budget for ${monthTitle(id)}. Saving replaces it.',
          confirmLabel: 'Replace',
        );
        if (!replace || !mounted) return;
      }
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
      id: id,
      monthKey: DateKeys.ofMonth(_start),
      income: income,
      categories: [...lines, ...carried],
      title: _title.text.trim(),
      periodType: _type,
      startDay: period.startDay,
      endDay: period.endDay,
    );

    // Saved on the device at once and confirmed by the server later, so close
    // the screen now instead of waiting (the device may be offline).
    final messenger = ScaffoldMessenger.of(context);
    widget.data.budgets
        .saveBudget(budget)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the budget'));
    widget.data.profile.markOnboardingComplete().then((_) {}, onError: (Object _) {});
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = widget.symbol;

    final income = _amountOf(_income);
    final pool = income - _sumOf(CategoryKind.fixed) - _sumOf(CategoryKind.savings);
    final unassigned = pool - _sumOf(CategoryKind.flexible);
    final days = BudgetPeriod(type: _type, start: _start, end: _end).totalDays;
    final perDay = (pool > 0 && !_end.isBefore(_start)) ? pool ~/ days : 0;
    final balance = widget.balance;

    String money(int minor) => Money.format(minor, symbol: symbol);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit budget' : 'New budget')),
      body: ListView(
        padding: Responsive.listPadding(context, maxWidth: 640, side: 20, top: 8),
        children: [
          Text('How long', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SegmentedButton<PeriodType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PeriodType.weekly, label: Text('Week')),
              ButtonSegment(value: PeriodType.monthly, label: Text('Month')),
              ButtonSegment(value: PeriodType.yearly, label: Text('Year')),
              ButtonSegment(value: PeriodType.custom, label: Text('Custom')),
            ],
            selected: {_type},
            onSelectionChanged: (selection) => _setType(selection.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DayButton(
                  label: 'Starts',
                  value: _start,
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime(DateTime.now().year + 3),
                  onChanged: _setStart,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DayButton(
                  label: 'Ends',
                  value: _end,
                  firstDate: _start,
                  lastDate: DateTime(_start.year + 10),
                  onChanged: _setEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _end.isBefore(_start)
                ? 'The end date is before the start date.'
                : '${plural(days, 'day')} · ${periodLabel(_start, _end)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _end.isBefore(_start) ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              hintText: 'For example Eid week',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 8),
          _MoneyField(
            controller: _income,
            label: 'Money to budget',
            symbol: symbol,
            icon: Icons.payments_outlined,
            errorText: _incomeError,
            onChanged: (_) => setState(() => _incomeError = null),
          ),
          const SizedBox(height: 8),
          if (balance != null)
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: Text('Use my balance: ${money(balance)}'),
                onPressed: balance <= 0
                    ? null
                    : () => setState(() {
                          _income.text = amountForField(balance);
                          _incomeError = null;
                        }),
              ),
            )
          else
            Text(
              'Tip: set your opening balance on the dashboard to budget against what you have.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
                        ? 'Fixed bills and savings are more than the money you are budgeting.'
                        : 'The budget minus fixed bills and savings. About ${money(perDay)} a day.',
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
          _section(context, 'Savings goal', 'What you want to keep during this budget.', CategoryKind.savings),
          _section(context, 'Everyday spending', 'A limit for each kind of daily spending.', CategoryKind.flexible),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_editing ? 'Save budget' : 'Create budget'),
          ),
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
