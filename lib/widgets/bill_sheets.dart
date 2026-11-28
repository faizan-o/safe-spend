import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/money.dart';
import '../models/recurring.dart';
import '../utils/category_icons.dart';
import '../utils/formatters.dart';
import 'form_bits.dart';

/// Opens the sheet for adding a bill (rent, electricity, a school fee...) or a
/// standing income, or editing [existing]. Completes with true when saved or
/// deleted.
Future<bool?> showRecurringSheet(
  BuildContext context, {
  required UserData data,
  required List<ExpenseCategory> categories,
  required String symbol,
  RecurringItem? existing,
  RecurringType type = RecurringType.expense,
}) {
  return showAppSheet<bool>(
    context,
    (_) => RecurringSheet(
      data: data,
      categories: categories,
      symbol: symbol,
      existing: existing,
      initialType: type,
    ),
  );
}

class RecurringSheet extends StatefulWidget {
  const RecurringSheet({
    super.key,
    required this.data,
    required this.categories,
    required this.symbol,
    this.existing,
    this.initialType = RecurringType.expense,
  });

  final UserData data;
  final List<ExpenseCategory> categories;
  final String symbol;
  final RecurringItem? existing;
  final RecurringType initialType;

  @override
  State<RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends State<RecurringSheet> {
  static const List<int> _remindOptions = [0, 1, 3, 7];

  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : amountForField(widget.existing!.amount),
  );
  late final TextEditingController _note = TextEditingController(text: widget.existing?.note ?? '');
  late final TextEditingController _interval =
      TextEditingController(text: (widget.existing?.interval ?? 1).toString());

  late RecurringType _type = widget.existing?.type ?? widget.initialType;
  late Frequency _frequency = widget.existing?.frequency ?? Frequency.monthly;
  late DateTime _due = widget.existing?.nextDue ?? DateKeys.startOfDay(DateTime.now());
  late DateTime? _end = DateKeys.parseDay(widget.existing?.endDay);
  late bool _auto = widget.existing?.autoRecord ?? false;
  late int _remind = widget.existing?.remindDays ?? 3;
  ExpenseCategory? _category;

  String? _titleError;
  String? _amountError;

  bool get _editing => widget.existing != null && widget.existing!.id.isNotEmpty;
  bool get _isIncome => _type == RecurringType.income;

  late final List<ExpenseCategory> _categories = _withExistingCategory();

  List<ExpenseCategory> _withExistingCategory() {
    final list = [...widget.categories];
    final existing = widget.existing;
    final id = existing?.categoryId;
    if (existing != null && id != null && !list.any((c) => c.id == id)) {
      list.add(ExpenseCategory(
        id: id,
        name: existing.categoryName ?? id,
        iconKey: 'category',
        colorValue: 0xFF546E7A,
        kind: existing.categoryKind ?? CategoryKind.fixed,
      ));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    final id = widget.existing?.categoryId;
    for (final category in _categories) {
      if (category.id == id) _category = category;
    }
    if (_category == null) {
      // A new bill: rent-like things are usually "Bills & utilities".
      for (final category in _categories) {
        if (category.id == 'bills') _category = category;
      }
      if (_category == null) {
        for (final category in _categories) {
          if (category.kind == CategoryKind.fixed) {
            _category = category;
            break;
          }
        }
      }
      _category ??= _categories.isEmpty ? null : _categories.first;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final minor = Money.parse(_amount.text);
    final titleError = title.isEmpty ? 'Give it a name, like Rent' : null;
    String? amountError;
    if (minor == null || minor <= 0) {
      amountError = 'Enter an amount above zero';
    } else if (minor > maxAmountMinor) {
      amountError = 'That amount is too large';
    }
    setState(() {
      _titleError = titleError;
      _amountError = amountError;
    });
    if (titleError != null || amountError != null) return;

    final repeats = _frequency != Frequency.once;
    final parsedInterval = int.tryParse(_interval.text.trim()) ?? 1;
    final interval = (!repeats || parsedInterval < 1) ? 1 : parsedInterval;
    final dueDay = DateKeys.ofDay(_due);
    final end = repeats ? _end : null;
    final category = _category;
    final existing = widget.existing;

    final RecurringItem item;
    if (existing != null) {
      // The day of the month a repeating bill falls on follows the due date.
      final startDay = existing.nextDueDay == dueDay ? existing.startDay : dueDay;
      item = existing.copyWith(
        title: title,
        type: _type,
        amount: minor!,
        categoryId: _isIncome ? null : category?.id,
        categoryName: _isIncome ? null : category?.name,
        categoryKind: _isIncome ? null : category?.kind,
        frequency: _frequency,
        interval: interval,
        startDay: startDay,
        nextDueDay: dueDay,
        endDay: end == null ? null : DateKeys.ofDay(end),
        clearEndDay: end == null,
        autoRecord: _auto,
        remindDays: _remind,
        note: _note.text.trim(),
        // Setting a new due date on a finished bill brings it back.
        active: true,
      );
    } else {
      item = RecurringItem(
        title: title,
        type: _type,
        amount: minor!,
        categoryId: _isIncome ? null : category?.id,
        categoryName: _isIncome ? null : category?.name,
        categoryKind: _isIncome ? null : category?.kind,
        frequency: _frequency,
        interval: interval,
        startDay: dueDay,
        nextDueDay: dueDay,
        endDay: end == null ? null : DateKeys.ofDay(end),
        autoRecord: _auto,
        remindDays: _remind,
        note: _note.text.trim(),
      );
    }

    final messenger = ScaffoldMessenger.of(context);
    final Future<void> write = !_editing
        ? widget.data.recurring.add(item).then((_) {})
        : widget.data.recurring.update(item);
    write.then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the bill'));
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete "${existing.title}"?',
      message: 'It stops being tracked. Expenses already recorded from it stay.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    widget.data.recurring
        .delete(existing.id)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger));
  }

  Future<void> _togglePause() async {
    final existing = widget.existing;
    if (existing == null) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    widget.data.recurring
        .setActive(existing, !existing.active)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repeats = _frequency != Frequency.once;
    final now = DateTime.now();

    return SheetFrame(
      title: _editing
          ? (_isIncome ? 'Edit expected income' : 'Edit bill')
          : (_isIncome ? 'Add expected income' : 'Add a bill'),
      subtitle: _isIncome
          ? 'A salary or other income you expect on a date.'
          : 'Rent, electricity, a school fee... SafeSpend reminds you before it is due.',
      children: [
        if (!_editing)
          SegmentedButton<RecurringType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: RecurringType.expense, label: Text('Bill'), icon: Icon(Icons.receipt_long_outlined)),
              ButtonSegment(value: RecurringType.income, label: Text('Income'), icon: Icon(Icons.south_west)),
            ],
            selected: {_type},
            onSelectionChanged: (selection) => setState(() => _type = selection.first),
          ),
        if (!_editing) const SizedBox(height: 16),
        TextField(
          controller: _title,
          maxLength: 60,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: _isIncome ? 'Name (for example Salary)' : 'Name (for example Rent)',
            errorText: _titleError,
          ),
          onChanged: (_) => setState(() => _titleError = null),
        ),
        const SizedBox(height: 4),
        AmountField(
          controller: _amount,
          symbol: widget.symbol,
          label: _isIncome ? 'Expected amount' : 'Amount',
          errorText: _amountError,
          onChanged: (_) => setState(() => _amountError = null),
        ),
        if (!_isIncome) ...[
          const SizedBox(height: 20),
          Text('Category', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in _categories)
                ChoiceChip(
                  avatar: Icon(iconForKey(category.iconKey), size: 18, color: Color(category.colorValue)),
                  label: Text(category.name),
                  selected: _category?.id == category.id,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Text('How often', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final frequency in Frequency.values)
              ChoiceChip(
                label: Text(frequency.label),
                selected: _frequency == frequency,
                onSelected: (_) => setState(() => _frequency = frequency),
              ),
          ],
        ),
        if (repeats) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Every'),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              Text(_frequency.unit),
            ],
          ),
        ],
        const SizedBox(height: 16),
        DayButton(
          label: repeats ? 'Next due' : 'Due',
          value: _due,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 10),
          onChanged: (day) => setState(() => _due = DateKeys.startOfDay(day)),
        ),
        if (repeats) ...[
          const SizedBox(height: 8),
          DayButton(
            label: 'Ends (optional)',
            value: _end,
            firstDate: _due,
            lastDate: DateTime(now.year + 20),
            onChanged: (day) => setState(() => _end = DateKeys.startOfDay(day)),
            onClear: () => setState(() => _end = null),
          ),
        ],
        const SizedBox(height: 16),
        Text('Remind me', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in _remindOptions)
              ChoiceChip(
                label: Text(days == 0 ? 'On the day' : '${plural(days, 'day')} before'),
                selected: _remind == days,
                onSelected: (_) => setState(() => _remind = days),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _auto,
          onChanged: (value) => setState(() => _auto = value),
          title: Text(_isIncome ? 'Record it automatically' : 'Record it automatically when due'),
          subtitle: Text(
            _isIncome
                ? 'Adds the income on its date. Turn off to confirm each time.'
                : 'For rent or fixed bills that always cost the same. Turn off to confirm each time.',
          ),
        ),
        TextField(
          controller: _note,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _save, child: Text(_editing ? 'Save changes' : 'Save')),
        if (_editing) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _togglePause,
            icon: Icon(widget.existing!.active ? Icons.pause_circle_outline : Icons.play_circle_outline),
            label: Text(widget.existing!.active ? 'Pause' : 'Resume'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ],
    );
  }
}

/// Opens the sheet for paying a bill (or confirming income received): the
/// real amount and the day can be changed, and a repeating bill moves on to
/// its next due date. Completes with true when saved.
Future<bool?> showMarkPaidSheet(
  BuildContext context, {
  required UserData data,
  required RecurringItem item,
  required String symbol,
}) {
  return showAppSheet<bool>(
    context,
    (_) => MarkPaidSheet(data: data, item: item, symbol: symbol),
  );
}

class MarkPaidSheet extends StatefulWidget {
  const MarkPaidSheet({super.key, required this.data, required this.item, required this.symbol});

  final UserData data;
  final RecurringItem item;
  final String symbol;

  @override
  State<MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<MarkPaidSheet> {
  late final TextEditingController _amount =
      TextEditingController(text: amountForField(widget.item.amount));
  late DateTime _date = DateTime.now();
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _pay() {
    final minor = Money.parse(_amount.text);
    if (minor == null || minor <= 0) {
      setState(() => _amountError = 'Enter an amount above zero');
      return;
    }
    if (minor > maxAmountMinor) {
      setState(() => _amountError = 'That amount is too large');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    widget.data.recurring
        .markPaid(widget.item, amount: minor, paidOn: _date)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the payment'));
    Navigator.of(context).pop(true);
  }

  void _skip() {
    final messenger = ScaffoldMessenger.of(context);
    widget.data.recurring
        .skip(widget.item)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final today = DateTime.now();
    final overdueText = dueText(item.daysUntilDue(today));
    return SheetFrame(
      title: item.title,
      subtitle: '$overdueText · ${shortDate(item.nextDue)}',
      children: [
        AmountField(
          controller: _amount,
          symbol: widget.symbol,
          label: item.isIncome ? 'Amount received' : 'Amount paid',
          autofocus: true,
          errorText: _amountError,
          onChanged: (_) => setState(() => _amountError = null),
        ),
        const SizedBox(height: 4),
        Text(item.isIncome ? 'Received on' : 'Paid on', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DateTimeFields(value: _date, showTime: false, onChanged: (value) => setState(() => _date = value)),
        const SizedBox(height: 20),
        FilledButton(onPressed: _pay, child: Text(item.isIncome ? 'Mark received' : 'Mark paid')),
        if (item.frequency != Frequency.once) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: _skip, child: const Text('Skip this time')),
        ],
      ],
    );
  }
}
