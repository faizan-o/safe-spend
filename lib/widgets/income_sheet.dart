import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/income.dart';
import '../models/money.dart';
import '../utils/formatters.dart';
import 'form_bits.dart';

/// Opens the bottom sheet for adding income, or editing [existing].
/// Completes with true when something was saved or deleted.
Future<bool?> showIncomeSheet(
  BuildContext context, {
  required UserData data,
  required String symbol,
  Income? existing,
}) {
  return showAppSheet<bool>(
    context,
    (_) => IncomeSheet(data: data, symbol: symbol, existing: existing),
  );
}

class IncomeSheet extends StatefulWidget {
  const IncomeSheet({super.key, required this.data, required this.symbol, this.existing});

  final UserData data;
  final String symbol;
  final Income? existing;

  @override
  State<IncomeSheet> createState() => _IncomeSheetState();
}

class _IncomeSheetState extends State<IncomeSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : amountForField(widget.existing!.amount),
  );
  late final TextEditingController _source =
      TextEditingController(text: widget.existing?.source ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _date = widget.existing?.date ?? DateTime.now();

  String? _amountError;
  String? _sourceError;

  bool get _editing => widget.existing != null && widget.existing!.id.isNotEmpty;

  @override
  void dispose() {
    _amount.dispose();
    _source.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final minor = Money.parse(_amount.text);
    String? amountError;
    if (minor == null || minor <= 0) {
      amountError = 'Enter an amount above zero';
    } else if (minor > maxAmountMinor) {
      amountError = 'That amount is too large';
    }
    final source = _source.text.trim();
    final sourceError = source.isEmpty ? 'Say where it came from' : null;
    setState(() {
      _amountError = amountError;
      _sourceError = sourceError;
    });
    if (amountError != null || sourceError != null) return;

    final existing = widget.existing;
    final income = (existing != null)
        ? existing.copyWith(amount: minor!, source: source, note: _note.text.trim(), date: _date)
        : Income(amount: minor!, source: source, note: _note.text.trim(), date: _date);

    // Saved on the device at once and confirmed by the server later, so close
    // the sheet now instead of waiting (the device may be offline).
    final messenger = ScaffoldMessenger.of(context);
    final Future<void> write = (_editing && existing != null)
        ? widget.data.incomes.updateIncome(previous: existing, updated: income)
        : widget.data.incomes.addIncome(income).then((_) {});
    write.then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the income'));
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete this income?',
      message: 'It is removed from your balance and totals.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    deleteIncomeWithUndo(messenger, widget.data, existing, widget.symbol);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _source.text.trim().toLowerCase();
    return SheetFrame(
      title: _editing ? 'Edit income' : 'Add income',
      children: [
        AmountField(
          controller: _amount,
          symbol: widget.symbol,
          autofocus: !_editing,
          errorText: _amountError,
          onChanged: (_) {
            if (_amountError != null) setState(() => _amountError = null);
          },
        ),
        const SizedBox(height: 20),
        Text('Where from', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in incomeSources)
              ChoiceChip(
                label: Text(source),
                selected: typed == source.toLowerCase(),
                onSelected: (_) => setState(() {
                  _source.text = source;
                  _sourceError = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _source,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Source', errorText: _sourceError),
          onChanged: (_) => setState(() => _sourceError = null),
        ),
        TextField(
          controller: _note,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 4),
        DateTimeFields(value: _date, onChanged: (value) => setState(() => _date = value)),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: Text(_editing ? 'Save changes' : 'Save income')),
        if (_editing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete income'),
          ),
        ],
      ],
    );
  }
}

/// Deletes an income and offers to undo it. The delete is sent right away;
/// undo saves the same income again.
void deleteIncomeWithUndo(
  ScaffoldMessengerState messenger,
  UserData data,
  Income income,
  String symbol,
) {
  void reportError(Object error) => reportSaveError(messenger);

  data.incomes.deleteIncome(income).then((_) {}, onError: reportError);

  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text('Deleted ${formatMoney(income.amount, symbol)} · ${income.source}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            data.incomes
                .addIncome(Income(
                  amount: income.amount,
                  source: income.source,
                  note: income.note,
                  date: income.date,
                  recurringId: income.recurringId,
                ))
                .then((_) {}, onError: reportError);
          },
        ),
      ),
    );
}
