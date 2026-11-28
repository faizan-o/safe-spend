import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/user_profile.dart';
import '../notifications/notification_service.dart';

/// Settings for reminders and alerts, with buttons to check they work.
class NotificationSettingsCard extends StatefulWidget {
  const NotificationSettingsCard({super.key, required this.data});

  final UserData data;

  @override
  State<NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<NotificationSettingsCard> with WidgetsBindingObserver {
  final NotificationService _service = NotificationService.instance;
  bool? _allowed;
  bool _exact = true;
  List<PendingReminder> _pending = const [];
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The user may have changed a permission in the phone's settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!_service.supported) return;
    final allowed = await _service.hasPermission();
    final exact = await _service.canScheduleExact();
    final pending = await _service.pending();
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _exact = exact;
      _pending = pending;
    });
  }

  Future<void> _save(UserProfile profile, ReminderSettings next) async {
    try {
      await widget.data.profile.updateReminder(next);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not save that. Please try again.');
    }
    // The shell notices the changed profile and reschedules; look again soon after.
    await Future<void>.delayed(const Duration(seconds: 3));
    await _refresh();
  }

  Future<void> _allow() async {
    final granted = await _service.requestPermission();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _message = granted
          ? 'Notifications are on.'
          : 'Notifications are blocked. Turn them on for SafeSpend in your phone\'s settings.';
    });
  }

  Future<void> _pickTime(UserProfile profile, {required bool daily}) async {
    final r = profile.reminder;
    final picked = await showTimePicker(
      context: context,
      initialTime: daily ? TimeOfDay(hour: r.hour, minute: r.minute) : TimeOfDay(hour: r.dueHour, minute: 0),
    );
    if (picked == null) return;
    await _save(
      profile,
      daily ? r.copyWith(hour: picked.hour, minute: picked.minute) : r.copyWith(dueHour: picked.hour),
    );
  }

  Future<void> _testNow() async {
    if (_allowed != true) {
      await _allow();
      if (_allowed != true) return;
    }
    await _service.showTest();
    if (mounted) setState(() => _message = 'Sent. Pull down the notification shade to see it.');
  }

  Future<void> _testLater() async {
    if (_allowed != true) {
      await _allow();
      if (_allowed != true) return;
    }
    final ok = await _service.scheduleTest(seconds: 15);
    await _refresh();
    if (mounted) {
      setState(() => _message = ok
          ? 'A test is scheduled for 15 seconds from now. Close the app or lock the screen and wait.'
          : 'Could not schedule the test.');
    }
  }

  String _time(BuildContext context, int hour, int minute) =>
      TimeOfDay(hour: hour, minute: minute).format(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget shell(List<Widget> children) => Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    if (!_service.supported) {
      return shell([
        const ListTile(
          leading: Icon(Icons.notifications_off_outlined),
          title: Text('Reminders need the phone app'),
          subtitle: Text(
            'Bill, debt and daily reminders are sent by the Android and iOS apps. '
            'On the web, due items still show in the Bills tab.',
          ),
        ),
      ]);
    }

    return StreamBuilder<UserProfile?>(
      stream: widget.data.profile.watchProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) {
          return shell(const [ListTile(title: Text('Loading…'))]);
        }
        final r = profile.reminder;
        final allowed = _allowed;
        return shell([
          if (allowed == false)
            ListTile(
              leading: Icon(Icons.notifications_off_outlined, color: scheme.error),
              title: const Text('Notifications are off'),
              subtitle: const Text('Allow them to get reminders.'),
              trailing: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _allow,
                child: const Text('Allow'),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.edit_note_outlined),
            title: const Text('Daily reminder'),
            subtitle: Text('Asks you to log your spending at ${_time(context, r.hour, r.minute)}'),
            value: r.enabled,
            onChanged: (v) => _save(profile, r.copyWith(enabled: v)),
          ),
          if (r.enabled)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Reminder time'),
              trailing: TextButton(
                onPressed: () => _pickTime(profile, daily: true),
                child: Text(_time(context, r.hour, r.minute)),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.event_note_outlined),
            title: const Text('Bills and income due'),
            subtitle: const Text('Before the date, as set on each bill, and on the day'),
            value: r.bills,
            onChanged: (v) => _save(profile, r.copyWith(bills: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.handshake_outlined),
            title: const Text('Debts and loans due'),
            subtitle: const Text('3 days before, on the day, and when overdue'),
            value: r.debts,
            onChanged: (v) => _save(profile, r.copyWith(debts: v)),
          ),
          if (r.bills || r.debts)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Time for due-date reminders'),
              trailing: TextButton(
                onPressed: () => _pickTime(profile, daily: false),
                child: Text(_time(context, r.dueHour, 0)),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.pie_chart_outline),
            title: const Text('Budget alerts'),
            subtitle: const Text('When a category reaches 90% of its limit, and when it goes over'),
            value: r.budgetAlerts,
            onChanged: (v) => _save(profile, r.copyWith(budgetAlerts: v)),
          ),
          if (allowed == true && !_exact)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Reminders may arrive a few minutes late'),
              subtitle: const Text('Allow exact alarms for on-time reminders.'),
              trailing: TextButton(
                onPressed: () async {
                  await _service.requestExactAlarms();
                  await _refresh();
                },
                child: const Text('Allow'),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _testNow,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Send a test now'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _testLater,
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Test in 15 seconds'),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(_message!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              _pending.isEmpty
                  ? 'No reminders are scheduled yet.'
                  : '${_pending.length} reminders scheduled. Next: ${_pending.first.title}',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ]);
      },
    );
  }
}
