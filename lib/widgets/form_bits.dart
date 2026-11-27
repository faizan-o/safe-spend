import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/date_keys.dart';
import '../utils/formatters.dart';

/// The largest amount accepted anywhere: Rs. 1,000,000,000 in paisa.
const int maxAmountMinor = 100000000000;

/// Shows a modal bottom sheet with the app's usual look.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: builder,
  );
}

/// The frame of a form in a bottom sheet: a title, then [children] in a
/// scrolling column that moves up with the keyboard.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + keyboard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// A big money field: digits, commas and a dot only, with the currency symbol in front.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.symbol,
    this.label = 'Amount',
    this.errorText,
    this.autofocus = false,
    this.onChanged,
    this.helperText,
  });

  final TextEditingController controller;
  final String symbol;
  final String label;
  final String? errorText;
  final String? helperText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      textInputAction: TextInputAction.next,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '$symbol ',
        errorText: errorText,
        helperText: helperText,
      ),
      onChanged: onChanged,
    );
  }
}

/// Opens the date picker. [lastDate] defaults to today (no future dates).
Future<DateTime?> pickDay(
  BuildContext context, {
  required DateTime initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  final last = lastDate ?? DateTime(now.year, now.month, now.day);
  final first = firstDate ?? DateTime(now.year - 5);
  var start = DateKeys.startOfDay(initial);
  if (start.isAfter(last)) start = last;
  if (start.isBefore(first)) start = first;
  return showDatePicker(context: context, initialDate: start, firstDate: first, lastDate: last);
}

/// A date button (and optionally a time button) for editing when something happened.
/// Picking a day keeps the time of day, and picking a time keeps the day.
/// The result is never later than now.
class DateTimeFields extends StatelessWidget {
  const DateTimeFields({super.key, required this.value, required this.onChanged, this.showTime = true});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool showTime;

  DateTime _clamped(DateTime date) {
    final now = DateTime.now();
    return date.isAfter(now) ? now : date;
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await pickDay(context, initial: value);
    if (picked == null) return;
    onChanged(_clamped(DateTime(picked.year, picked.month, picked.day, value.hour, value.minute)));
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
    );
    if (picked == null) return;
    onChanged(_clamped(DateTime(value.year, value.month, value.day, picked.hour, picked.minute)));
  }

  @override
  Widget build(BuildContext context) {
    final dateButton = OutlinedButton.icon(
      onPressed: () => _pickDate(context),
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(dayLabel(value, DateTime.now())),
    );
    if (!showTime) return dateButton;
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    return Row(
      children: [
        Expanded(child: dateButton),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickTime(context),
            icon: const Icon(Icons.schedule, size: 18),
            label: Text('$hour12:$minute $suffix'),
          ),
        ),
      ],
    );
  }
}

/// A button that shows a day (no time) and opens the date picker.
/// [lastDate] and [firstDate] are not limited to the past, so it can be used
/// for due dates.
class DayButton extends StatelessWidget {
  const DayButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// When given, a clear (x) button is shown while a day is set.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final current = value;
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await pickDay(
                context,
                initial: current ?? now,
                firstDate: firstDate ?? DateTime(now.year - 5),
                lastDate: lastDate ?? DateTime(now.year + 10),
              );
              if (picked != null) onChanged(picked);
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(current == null ? label : '$label: ${shortDate(current)}'),
          ),
        ),
        if (current != null && onClear != null)
          IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: onClear),
      ],
    );
  }
}

/// Asks "are you sure?" and returns true when the user confirms.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Shows a short message at the bottom of the screen.
void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Reports a failed background save.
void reportSaveError(ScaffoldMessengerState messenger, [String what = 'the change']) {
  messenger.showSnackBar(SnackBar(content: Text('Could not save $what. Check your connection.')));
}
