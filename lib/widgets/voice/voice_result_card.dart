import 'package:flutter/material.dart';

import '../../models/expense.dart';
import '../../models/money.dart';
import '../../utils/category_icons.dart';
import '../../utils/formatters.dart';
import '../../voice/voice_controller.dart';
import '../../voice/voice_models.dart';

/// Shows what the workflow understood and lets the user save, edit or discard
/// it. When the workflow needs more detail or fails, it says so instead.
class VoiceResultCard extends StatelessWidget {
  const VoiceResultCard({super.key, required this.controller, required this.onEdit});

  final VoiceController controller;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    if (result == null) return const SizedBox.shrink();
    final draft = controller.draft;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: draft != null
            ? _Understood(controller: controller, result: result, draft: draft, onEdit: onEdit)
            : _NotUnderstood(controller: controller, result: result),
      ),
    );
  }
}

class _Understood extends StatelessWidget {
  const _Understood({
    required this.controller,
    required this.result,
    required this.draft,
    required this.onEdit,
  });

  final VoiceController controller;
  final VoiceWorkflowResult result;
  final Expense draft;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    var iconKey = 'category';
    var color = const Color(0xFF546E7A);
    for (final category in controller.categories) {
      if (category.id == draft.categoryId) {
        iconKey = category.iconKey;
        color = Color(category.colorValue);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Here is what I understood', style: theme.textTheme.labelLarge),
            const Spacer(),
            if (result.isDummy) const _TestModeChip(),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(iconForKey(iconKey), color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Money.format(draft.amount, symbol: controller.symbol, showDecimals: draft.amount % 100 != 0),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${draft.categoryName} · ${dayLabel(draft.date, DateTime.now())}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (draft.note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Note: ${draft.note}', style: theme.textTheme.bodyMedium),
        ],
        if (result.message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            result.message,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: controller.save,
          icon: const Icon(Icons.check),
          label: const Text('Save expense'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                onPressed: controller.discard,
                child: const Text('Discard'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotUnderstood extends StatelessWidget {
  const _NotUnderstood({required this.controller, required this.result});

  final VoiceController controller;
  final VoiceWorkflowResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final asking = result.status == VoiceWorkflowStatus.needsClarification;
    final fallback = switch (result.status) {
      VoiceWorkflowStatus.needsClarification => 'I need a bit more detail. Say it again with the amount.',
      VoiceWorkflowStatus.parsed => "I found an amount but couldn't match it to one of your categories.",
      VoiceWorkflowStatus.failed => "I couldn't understand that.",
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(asking ? Icons.help_outline : Icons.error_outline, color: asking ? scheme.primary : scheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.message.isNotEmpty ? result.message : fallback,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            if (result.isDummy) ...[const SizedBox(width: 8), const _TestModeChip()],
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: controller.startListening,
          icon: const Icon(Icons.mic),
          label: Text(asking ? 'Answer by voice' : 'Try again'),
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: controller.discard, child: const Text('Discard')),
      ],
    );
  }
}

class _TestModeChip extends StatelessWidget {
  const _TestModeChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Test mode',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer),
      ),
    );
  }
}
