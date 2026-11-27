import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../models/money.dart';
import '../utils/category_icons.dart';
import '../utils/formatters.dart';
import 'dashboard/expense_tile.dart';
import 'form_bits.dart';

/// Opens the bottom sheet for adding an expense, or editing [existing].
///
/// [existing] can also be a draft that has not been saved (an expense with an
/// empty id, such as one found by the voice workflow): the sheet then shows it
/// pre-filled and saves it as a new expense.
///
/// Everything can be changed: amount, category, shop, note, date and time, and
/// for a receipt the lines read from it. [onSaved] gets the expense as saved
/// (its id is empty for a new one).
///
/// Completes with true when the expense was saved or deleted, otherwise null.
Future<bool?> showExpenseSheet(
  BuildContext context, {
  required UserData data,
  required List<ExpenseCategory> categories,
  required String symbol,
  Expense? existing,
  void Function(String expenseId)? onAdded,
  void Function(Expense saved)? onSaved,
}) {
  return showAppSheet<bool>(
    context,
    (_) => ExpenseSheet(
      data: data,
      categories: categories,
      symbol: symbol,
      existing: existing,
      onAdded: onAdded,
      onSaved: onSaved,
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
    this.onAdded,
    this.onSaved,
  });

  /// Called with the new id when the sheet saved a new expense.
  final void Function(String expenseId)? onAdded;

  /// Called with the expense when the sheet saved it (new or edited).
  final void Function(Expense saved)? onSaved;

  final UserData data;
  final List<ExpenseCategory> categories;
  final String symbol;
  final Expense? existing;

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

/// The text fields of one receipt line.
class _ItemFields {
  _ItemFields({String description = '', String amount = '', int quantity = 1})
      : description = TextEditingController(text: description),
        amount = TextEditingController(text: amount),
        quantity = TextEditingController(text: quantity.toString());

  final TextEditingController description;
  final TextEditingController amount;
  final TextEditingController quantity;

  void dispose() {
    description.dispose();
    amount.dispose();
    quantity.dispose();
  }
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null || widget.existing!.amount <= 0 ? '' : amountForField(widget.existing!.amount),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late final TextEditingController _merchant =
      TextEditingController(text: widget.existing?.merchant ?? '');
  late final List<ExpenseCategory> _categories = _withExistingCategory();
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  final List<_ItemFields> _items = [];

  ExpenseCategory? _selected;
  String? _amountError;
  String? _categoryError;

  /// True when changing a saved expense; false for a new one or a draft.
  bool get _editing => widget.existing != null && widget.existing!.id.isNotEmpty;

  /// Receipts have lines that can be corrected.
  bool get _showItems =>
      widget.existing != null &&
      (widget.existing!.items.isNotEmpty || widget.existing!.source == ExpenseSource.receipt);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      for (final category in _categories) {
        if (category.id == existing.categoryId) _selected = category;
      }
      for (final item in existing.items) {
        _items.add(_ItemFields(
          description: item.description,
          amount: amountForField(item.amount),
          quantity: item.quantity,
        ));
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _merchant.dispose();
    for (final item in _items) {
      item.dispose();
    }
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

  /// The lines that are filled in properly (a description and an amount).
  List<ExpenseItem> _readItems() {
    final result = <ExpenseItem>[];
    for (final fields in _items) {
      final description = fields.description.text.trim();
      final amount = Money.parse(fields.amount.text);
      if (description.isEmpty || amount == null || amount <= 0) continue;
      final quantity = int.tryParse(fields.quantity.text.trim()) ?? 1;
      result.add(ExpenseItem(
        description: description,
        amount: amount,
        quantity: quantity < 1 ? 1 : quantity,
      ));
    }
    return result;
  }

  void _save() {
    final minor = Money.parse(_amount.text);
    String? amountError;
    if (minor == null || minor <= 0) {
      amountError = 'Enter an amount above zero';
    } else if (minor > maxAmountMinor) {
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
    final merchant = _merchant.text.trim();
    // Editing keeps everything the sheet does not show (source, transcript,
    // receipt link, ...).
    final expense = existing != null
        ? existing.copyWith(
            amount: minor!,
            category: category,
            note: _note.text.trim(),
            date: _date,
            merchant: merchant,
            items: _showItems ? _readItems() : null,
          )
        : Expense(
            amount: minor!,
            categoryId: category.id,
            categoryName: category.name,
            categoryKind: category.kind,
            note: _note.text.trim(),
            merchant: merchant.isEmpty ? null : merchant,
            date: _date,
          );

    // The write is queued locally at once and confirmed by the server later,
    // so close the sheet now instead of waiting (it may be offline).
    final messenger = ScaffoldMessenger.of(context);
    final onAdded = widget.onAdded;
    final Future<void> write = (!_editing || existing == null)
        ? widget.data.expenses.addExpense(expense).then((id) => onAdded?.call(id))
        : widget.data.expenses.updateExpense(previous: existing, updated: expense);
    write.then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the expense'));
    widget.onSaved?.call(expense);
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete this expense?',
      message: 'It is removed from your totals. You can undo it right after.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    deleteExpenseUndoable(messenger, widget.data, existing, widget.symbol);
  }

  int get _itemsTotal {
    var total = 0;
    for (final item in _readItems()) {
      total += item.amount;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsTotal = _itemsTotal;
    final typedAmount = Money.parse(_amount.text);

    return SheetFrame(
      title: _editing ? 'Edit expense' : 'Add expense',
      children: [
        AmountField(
          controller: _amount,
          symbol: widget.symbol,
          autofocus: !_editing,
          errorText: _amountError,
          onChanged: (_) => setState(() => _amountError = null),
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
          controller: _merchant,
          maxLength: 100,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Shop or payee (optional)'),
        ),
        TextField(
          controller: _note,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 4),
        DateTimeFields(value: _date, onChanged: (value) => setState(() => _date = value)),
        if (_showItems) ...[
          const SizedBox(height: 24),
          Text('Items on the receipt', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++) _itemEditor(context, i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _items.add(_ItemFields())),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
          ),
          if (itemsTotal > 0)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Items add up to ${formatMoney(itemsTotal, widget.symbol)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (typedAmount != itemsTotal)
                  TextButton(
                    onPressed: () => setState(() {
                      _amount.text = amountForField(itemsTotal);
                      _amountError = null;
                    }),
                    child: const Text('Use as total'),
                  ),
              ],
            ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _save,
          child: Text(_editing ? 'Save changes' : 'Save expense'),
        ),
        if (_editing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete expense'),
          ),
        ],
      ],
    );
  }

  Widget _itemEditor(BuildContext context, int index) {
    final fields = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: fields.description,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Item', isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: fields.quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: fields.amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Price', prefixText: '${widget.symbol} ', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Remove item',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _items.removeAt(index).dispose();
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
