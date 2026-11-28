import 'package:flutter/material.dart';

import '../../models/money.dart';
import '../../utils/formatters.dart';
import '../../voice/voice_controller.dart';
import '../../voice/voice_models.dart';

/// Shows an income, bill, debt, loan, repayment or opening balance that was
/// understood from speech. Nothing is saved yet: "Review and save" opens the
/// usual form with the values filled in.
class VoiceEntryCard extends StatelessWidget {
  const VoiceEntryCard({super.key, required this.controller, required this.entry, required this.onReview});

  final VoiceController controller;
  final VoiceEntry entry;
  final VoidCallback onReview;

  (IconData, String) get _kind => switch (entry.type) {
        VoiceEntryType.income => (Icons.south_west, 'Income'),
        VoiceEntryType.bill => (Icons.receipt_long_outlined, 'Bill'),
        VoiceEntryType.debt => (Icons.north_east, 'Debt (you owe)'),
        VoiceEntryType.loan => (Icons.handshake_outlined, 'Loan (owed to you)'),
        VoiceEntryType.repayment => (Icons.payments_outlined, 'Repayment'),
        VoiceEntryType.openingBalance => (Icons.account_balance_wallet_outlined, 'Opening balance'),
      };

  String get _summary {
    final parts = <String>[];
    void add(String? text) {
      if (text != null && text.trim().isNotEmpty) parts.add(text.trim());
    }

    switch (entry.type) {
      case VoiceEntryType.income:
        add(entry.source);
      case VoiceEntryType.bill:
        add(entry.title);
        add(entry.frequency == null || entry.frequency == 'once' ? null : entry.frequency);
        if (entry.dueDate != null) add('due ${shortDate(entry.dueDate!)}');
      case VoiceEntryType.debt:
      case VoiceEntryType.loan:
        add(entry.person);
        if (entry.dueDate != null) add('pay back by ${shortDate(entry.dueDate!)}');
      case VoiceEntryType.repayment:
        add(entry.person);
      case VoiceEntryType.openingBalance:
        break;
    }
    if (entry.date != null) add(shortDate(entry.date!));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, label) = _kind;
    final minor = Money.fromMajor(entry.amount);
    final summary = _summary;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                      Text(
                        Money.format(minor, symbol: controller.symbol, showDecimals: minor % 100 != 0),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(summary, style: theme.textTheme.bodyLarge),
            ],
            if (controller.result?.message.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                controller.result!.message,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.check),
              label: const Text('Review and save'),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: controller.discard, child: const Text('Discard')),
          ],
        ),
      ),
    );
  }
}
