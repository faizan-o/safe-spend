import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/expense.dart';
import '../models/money.dart';
import '../utils/category_icons.dart';
import '../utils/formatters.dart';

/// Opens the bottom sheet for adding an expense, or editing [existing].
///
/// [existing] can also be a draft that has not been saved (an expense with an
/// empty id, such as one found by the voice workflow): the sheet then shows it
/// pre-filled and saves it as a new expense.
///
/// Completes with true when the expense was saved, otherwise null.
Future<bool?> showExpenseSheet(
  BuildContext context, {
  required UserData data,
  required List<ExpenseCategory> categories,
  required String symbol,
  Expense? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ExpenseSheet(
      data: data,
      categories: categories,
      symbol: symbol,
      existing: existing,
    ),
  );
}

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({
    super.key,
    required this.data,
    required this.categories,
    required this.symbol,
    this.existing,
  });

  final UserData data;
  final List<ExpenseCategory> categories;
  final String symbol;
  final Expense? existing;

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  static const int _maxAmount = 100000000000; // Rs. 1,000,000,000 in paisa

  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : amountForField(widget.existing!.amount),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late final List<ExpenseCategory> _categories = _withExistingCategory();
  late DateTime _date = widget.existing?.date ?? DateTime.now();

  ExpenseCategory? _selected;
  String? _amountError;
  String? _categoryError;

  /// True when changing a saved expense; false for a new one or a draft.
  bool get _editing => widget.existing != null && widget.existing!.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      for (final category in _categories) {
        if (category.id == existing.categoryId) _selected = category;
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// When editing an expense whose category has since been archived, keep that
  /// category available so the expense can still be shown and saved.
  List<ExpenseCategory> _withExistingCategory() {
    final list = [...widget.categories];
    final existing = widget.existing;
    if (existing != null && !list.any((c) => c.id == existing.categoryId)) {
      list.add(ExpenseCategory(
        id: existing.categoryId,
        name: existing.categoryName,
        iconKey: 'category',
        colorValue: 0xFF546E7A,
        kind: existing.categoryKind,
      ));
    }
    return list;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Keeps the original time when the day did not change; otherwise uses the
  /// chosen day with the current time of day.
  DateTime _resolveDate() {
    final original = widget.existing?.date;
    if (original != null && DateKeys.ofDay(original) == DateKeys.ofDay(_date)) {
      return original;
    }
    final now = DateTime.now();
    return DateTime(_date.year, _date.month, _date.day, now.hour, now.minute);
  }

  void _save() {
    final minor = Money.parse(_amount.text);
    String? amountError;
    if (minor == null || minor <= 0) {
      amountError = 'Enter an amount above zero';
    } else if (minor > _maxAmount) {
      amountError = 'That amount is too large';
    }
    final categoryError = _selected == null ? 'Choose a category' : null;

    setState(() {
      _amountError = amountError;
      _categoryError = categoryError;
    });
    if (amountError != null || categoryError != null) return;

    final category = _selected!;
    final existing = widget.existing;
    final expense = Expense(
      id: existing?.id ?? '',
      amount: minor!,
      categoryId: category.id,
      categoryName: category.name,
      categoryKind: category.kind,
      note: _note.text.trim(),
      date: _resolveDate(),
      source: existing?.source ?? ExpenseSource.manual,
      transcript: existing?.transcript,
    );

    // The write is queued locally at once and confirmed by the server later,
    // so close the sheet now instead of waiting (it may be offline).
    final messenger = ScaffoldMessenger.of(context);
    final Future<void> write = (!_editing || existing == null)
        ? widget.data.expenses.addExpense(expense)
        : widget.data.expenses.updateExpense(previous: existing, updated: expense);
    write.then((_) {}, onError: (Object error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save the expense. Check your connection.')),
      );
    });
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final now = DateTime.now();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + keyboard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editing ? 'Edit expense' : 'Add expense',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: !_editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            textInputAction: TextInputAction.next,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '${widget.symbol} ',
              errorText: _amountError,
            ),
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
          const SizedBox(height: 20),
          Text('Category', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_categories.isEmpty)
            const Text('Categories are still being set up. Close this and try again in a moment.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in _categories)
                  ChoiceChip(
                    avatar: Icon(
                      iconForKey(category.iconKey),
                      size: 18,
                      color: Color(category.colorValue),
                    ),
                    label: Text(category.name),
                    selected: _selected?.id == category.id,
                    onSelected: (_) => setState(() {
                      _selected = category;
                      _categoryError = null;
                    }),
                  ),
              ],
            ),
          if (_categoryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _categoryError!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(dayLabel(_date, now)),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(_editing ? 'Save changes' : 'Save expense'),
          ),
        ],
      ),
    );
  }
}
