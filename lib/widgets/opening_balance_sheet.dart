import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/date_keys.dart';
import '../models/money.dart';
import '../utils/formatters.dart';
import 'form_bits.dart';

/// Opens the sheet where the user enters the money they have now (their
/// opening balance). Completes with true when it was saved.
Future<bool?> showOpeningBalanceSheet(
  BuildContext context, {
  required UserData data,
  required String symbol,
  int? currentAmount,
  DateTime? currentDay,
}) {
  return showAppSheet<bool>(
    context,
    (_) => OpeningBalanceSheet(
      data: data,
      symbol: symbol,
      currentAmount: currentAmount,
      currentDay: currentDay,
    ),
  );
}

class OpeningBalanceSheet extends StatefulWidget {
  const OpeningBalanceSheet({
    super.key,
    required this.data,
    required this.symbol,
    this.currentAmount,
    this.currentDay,
  });

  final UserData data;
  final String symbol;
  final int? currentAmount;
  final DateTime? currentDay;

  @override
  State<OpeningBalanceSheet> createState() => _OpeningBalanceSheetState();
}

class _OpeningBalanceSheetState extends State<OpeningBalanceSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.currentAmount == null ? '' : amountForField(widget.currentAmount!),
  );
  late DateTime _day = widget.currentDay ?? DateKeys.startOfDay(DateTime.now());
  String? _error;

  bool get _editing => widget.currentAmount != null;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final minor = Money.parse(_amount.text);
    if (minor == null) {
      setState(() => _error = 'Enter the money you have (0 if none)');
      return;
    }
    if (minor > maxAmountMinor) {
      setState(() => _error = 'That amount is too large');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    widget.data.profile
        .updateOpeningBalance(amount: minor, day: _day)
        .then((_) {}, onError: (Object error) => reportSaveError(messenger, 'the opening balance'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: _editing ? 'Edit opening balance' : 'Set your opening balance',
      subtitle: 'The money you have on the day you start. SafeSpend adds your income and takes off '
          'your spending from that day on, so you always see what you have now. '
          'Budgets are then made against it.',
      children: [
        AmountField(
          controller: _amount,
          symbol: widget.symbol,
          label: 'Money I have',
          autofocus: !_editing,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 16),
        Text('As of', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DateTimeFields(
          value: _day,
          showTime: false,
          onChanged: (value) => setState(() => _day = DateKeys.startOfDay(value)),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
