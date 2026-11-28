import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/date_keys.dart';
import '../models/debt.dart';
import '../models/money.dart';
import '../utils/formatters.dart';
import 'form_bits.dart';

/// Opens the sheet for adding a debt (money I owe) or a loan (money I am
/// owed), or editing [existing]. Completes with true when saved or deleted.
Future<bool?> showDebtSheet(
  BuildContext context, {
  required UserData data,
  required String symbol,
  Debt? existing,
  DebtDirection direction = DebtDirection.owedByMe,
}) {
  return showAppSheet<bool>(
    context,
    (_) => DebtSheet(data: data, symbol: symbol, existing: existing, initialDirection: direction),
  );
}

class DebtSheet extends StatefulWidget {
  const DebtSheet({
    super.key,
    required this.data,
    required this.symbol,
    this.existing,
    this.initialDirection = DebtDirection.owedByMe,
  });

  final UserData data;
  final String symbol;
  final Debt? existing;
  final DebtDirection initialDirection;

  @override
  State<DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends State<DebtSheet> {
  late final TextEditingController _person = TextEditingController(text: widget.existing?.person ?? '');
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null ? '' : amountForField(widget.existing!.amount),
  );
  late final TextEditingController _note = TextEditingController(text: widget.existing?.note ?? '');
  late DebtDirection _direction = widget.existing?.direction ?? widget.initialDirection;
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late DateTime? _due = DateKeys.parseDay(widget.existing?.dueDay);
  late bool _affectsBalance = widget.existing?.affectsBalance ?? true;
  String? _personError;
  String? _amountError;

  /// False for a new debt and for a draft that came from voice (no id yet).
  bool get _editing => widget.existing != null && widget.existing!.id.isNotEmpty;
  bool get _lent => _direction == DebtDirection.owedToMe;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final person = _person.text.trim();
    final minor = Money.parse(_amount.text);
    final personError = person.isEmpty ? 'Who is it with?' : null;
    String? amountError;
    final paid = widget.existing?.paid ?? 0;
    if (minor == null || minor <= 0) {
      amountError = 'Enter an amount above zero';
    } else if (minor > maxAmountMinor) {
      amountError = 'That amount is too large';
    } else if (minor < paid) {
      amountError = 'Already repaid ${formatMoney(paid, widget.symbol)}, so it cannot be less';
    }
    setState(() {
      _personError = personError;
      _amountError = amountError;
    });
    if (personError != null || amountError != null) return;

    final existing = widget.existing;
    final due = _due;
    final Debt debt;
    if (existing != null) {
      debt = existing.copyWith(
        direction: _direction,
        person: person,
        amount: minor!,
        date: _date,
        dueDay: due == null ? null : DateKeys.ofDay(due),
        clearDueDay: due == null,
        note: _note.text.trim(),
        affectsBalance: _affectsBalance,
      );
    } else {
      debt = Debt(
        direction: _direction,
        person: person,
        amount: minor!,
        date: _date,
        dueDay: due == null ? null : DateKeys.ofDay(due),
        note: _note.text.trim(),
        affectsBalance: _affectsBalance,
      );
    }

    final messenger = ScaffoldMessenger.of(context);
    final Future<void> write =
        !_editing ? widget.data.debts.add(debt).then((_) {}) : widget.data.debts.update(debt);
    write.then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the debt'));
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete this ${existing.isOwedToMe ? 'loan' : 'debt'}?',
      message: 'It and its repayments are removed, and your balance changes back.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    widget.data.debts
        .delete(existing.id)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return SheetFrame(
      title: _editing ? (_lent ? 'Edit loan' : 'Edit debt') : (_lent ? 'Add a loan' : 'Add a debt'),
      subtitle: _lent ? 'Money you lent and are waiting to get back.' : 'Money you borrowed and have to pay back.',
      children: [
        SegmentedButton<DebtDirection>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: DebtDirection.owedByMe, label: Text('I owe'), icon: Icon(Icons.north_east)),
            ButtonSegment(value: DebtDirection.owedToMe, label: Text('Owed to me'), icon: Icon(Icons.south_west)),
          ],
          selected: {_direction},
          onSelectionChanged: (selection) => setState(() => _direction = selection.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _person,
          maxLength: 60,
          autofocus: !_editing,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: _lent ? 'Who owes you' : 'Who you owe',
            errorText: _personError,
          ),
          onChanged: (_) => setState(() => _personError = null),
        ),
        const SizedBox(height: 4),
        AmountField(
          controller: _amount,
          symbol: widget.symbol,
          label: _lent ? 'Amount lent' : 'Amount borrowed',
          errorText: _amountError,
          onChanged: (_) => setState(() => _amountError = null),
        ),
        const SizedBox(height: 4),
        Text(_lent ? 'Lent on' : 'Borrowed on', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        DateTimeFields(value: _date, showTime: false, onChanged: (value) => setState(() => _date = value)),
        const SizedBox(height: 8),
        DayButton(
          label: 'Pay back by (optional)',
          value: _due,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 20),
          onChanged: (day) => setState(() => _due = DateKeys.startOfDay(day)),
          onClear: () => setState(() => _due = null),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _affectsBalance,
          onChanged: (value) => setState(() => _affectsBalance = value),
          title: const Text('Count it in my balance'),
          subtitle: Text(
            _lent
                ? 'The money you lent leaves your balance, and comes back as it is repaid.'
                : 'The money you borrowed is added to your balance, and leaves as you repay it. '
                    'Turn off if it was already in your opening balance.',
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
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(_lent ? 'Delete loan' : 'Delete debt'),
          ),
        ],
      ],
    );
  }
}

/// Opens the sheet for a repayment on [debt] (or editing [payment]).
/// Completes with true when saved or deleted.
Future<bool?> showRepaymentSheet(
  BuildContext context, {
  required UserData data,
  required Debt debt,
  required String symbol,
  DebtPayment? payment,
  int? amount,
}) {
  return showAppSheet<bool>(
    context,
    (_) => RepaymentSheet(data: data, debt: debt, symbol: symbol, payment: payment, amount: amount),
  );
}

class RepaymentSheet extends StatefulWidget {
  const RepaymentSheet({
    super.key,
    required this.data,
    required this.debt,
    required this.symbol,
    this.payment,
    this.amount,
  });

  final UserData data;
  final Debt debt;
  final String symbol;
  final DebtPayment? payment;

  /// A suggested amount (from voice), used for a new repayment.
  final int? amount;

  @override
  State<RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends State<RepaymentSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: amountForField(widget.payment?.amount ?? _suggested),
  );
  late final TextEditingController _note = TextEditingController(text: widget.payment?.note ?? '');
  late DateTime _date = widget.payment?.date ?? DateTime.now();
  String? _amountError;

  bool get _editing => widget.payment != null;

  int get _suggested {
    final wanted = widget.amount;
    if (wanted == null || wanted <= 0) return widget.debt.remaining;
    return wanted > widget.debt.remaining ? widget.debt.remaining : wanted;
  }

  /// The most this payment can be: what is left, plus this payment's own old
  /// amount when editing it.
  int get _limit => widget.debt.remaining + (widget.payment?.amount ?? 0);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final minor = Money.parse(_amount.text);
    String? error;
    if (minor == null || minor <= 0) {
      error = 'Enter an amount above zero';
    } else if (minor > _limit) {
      error = 'Only ${formatMoney(_limit, widget.symbol)} is left to repay';
    }
    if (error != null) {
      setState(() => _amountError = error);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final existing = widget.payment;
    final Future<void> write;
    if (existing == null) {
      write = widget.data.debts
          .addPayment(
            widget.debt,
            DebtPayment(id: '', amount: minor!, date: _date, note: _note.text.trim()),
          )
          .then((_) {});
    } else {
      write = widget.data.debts
          .updatePayment(widget.debt, existing.copyWith(amount: minor!, date: _date, note: _note.text.trim()))
          .then((_) {});
    }
    write.then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the repayment'));
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final payment = widget.payment;
    if (payment == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete this repayment?',
      message: 'The amount counts as unpaid again.',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    widget.data.debts
        .deletePayment(widget.debt, payment.id)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger));
  }

  @override
  Widget build(BuildContext context) {
    final lent = widget.debt.isOwedToMe;
    return SheetFrame(
      title: _editing ? 'Edit repayment' : (lent ? 'Money received back' : 'Add a repayment'),
      subtitle: '${widget.debt.person} · ${formatMoney(widget.debt.remaining, widget.symbol)} still unpaid',
      children: [
        AmountField(
          controller: _amount,
          symbol: widget.symbol,
          label: lent ? 'Amount received' : 'Amount paid',
          autofocus: true,
          errorText: _amountError,
          onChanged: (_) => setState(() => _amountError = null),
        ),
        const SizedBox(height: 4),
        DateTimeFields(value: _date, showTime: false, onChanged: (value) => setState(() => _date = value)),
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
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete repayment'),
          ),
        ],
      ],
    );
  }
}
