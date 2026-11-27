import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../data/user_data.dart';
import '../models/date_keys.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../settings/theme_controller.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/opening_balance_sheet.dart';

void openSettings(BuildContext context, AuthService auth, AuthUser user, {UserData? data}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SettingsScreen(auth: auth, user: user, data: data)),
  );
}

/// App settings. Today: the appearance (light, dark or follow the device).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.auth, required this.user, this.data});

  /// Needed for the testing tools; null in demo mode.
  final UserData? data;

  final AuthService auth;
  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: Responsive.listPadding(context, maxWidth: 640, top: 16, bottom: 16),
        children: [
          _SectionLabel('Appearance'),
          ListenableBuilder(
            listenable: themeController,
            builder: (context, _) => Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Column(
                children: [
                  _ThemeOption(mode: ThemeMode.dark, title: 'Dark', subtitle: 'Deep navy with aqua accents', icon: Icons.dark_mode_outlined),
                  _ThemeOption(mode: ThemeMode.light, title: 'Light', subtitle: 'Bright background, easier in sunlight', icon: Icons.light_mode_outlined),
                  _ThemeOption(mode: ThemeMode.system, title: 'Match my device', subtitle: 'Switches with your phone or computer', icon: Icons.brightness_auto_outlined),
                ],
              ),
            ),
          ),
          if (data != null) ...[
            const SizedBox(height: 24),
            _SectionLabel('Money'),
            _OpeningBalanceCard(data: data!),
          ],
          const SizedBox(height: 24),
          _SectionLabel('Account'),
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user.displayName?.trim().isNotEmpty == true ? user.displayName! : user.firstName),
                  subtitle: Text(user.email),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    unawaited(auth.signOut());
                  },
                ),
              ],
            ),
          ),
          if (data != null) ...[
            const SizedBox(height: 24),
            _SectionLabel('Testing'),
            _SampleDataCard(data: data!),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(AppConfig.appName, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Shows the opening balance and lets the user change it.
class _OpeningBalanceCard extends StatelessWidget {
  const _OpeningBalanceCard({required this.data});

  final UserData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<UserProfile?>(
      stream: data.profile.watchProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final symbol = profile?.currencySymbol ?? 'Rs.';
        final has = profile != null && profile.hasOpeningBalance;
        return Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Opening balance'),
            subtitle: Text(
              has
                  ? '${formatMoney(profile.openingBalance, symbol)} on ${shortDate(DateKeys.parseDay(profile.openingBalanceDay) ?? DateTime.now())}'
                  : 'Not set. Enter the money you have now.',
            ),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: profile == null
                ? null
                : () => showOpeningBalanceSheet(
                      context,
                      data: data,
                      symbol: symbol,
                      currentAmount: has ? profile.openingBalance : null,
                      currentDay: has ? DateKeys.parseDay(profile.openingBalanceDay) : null,
                    ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.mode, required this.title, required this.subtitle, required this.icon});

  final ThemeMode mode;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final selected = themeController.mode == mode;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? scheme.primary : scheme.outline,
      ),
      selected: selected,
      onTap: () => unawaited(themeController.setMode(mode)),
    );
  }
}

/// Adds a month of realistic expenses so the dashboard, flags and the monthly
/// report can be tried without typing everything in.
class _SampleDataCard extends StatefulWidget {
  const _SampleDataCard({required this.data});

  final UserData data;

  @override
  State<_SampleDataCard> createState() => _SampleDataCardState();
}

class _SampleDataCardState extends State<_SampleDataCard> {
  bool _busy = false;
  int _done = 0;

  Future<void> _run() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add sample data?'),
        content: const Text(
          'This adds about 100 test expenses for last month and this month, and a budget for each '
          'month that has none. It is meant for trying the app and the monthly report.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _done = 0;
    });
    String message;
    try {
      final count = await SampleData.load(
        widget.data,
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
      );
      message = 'Added $count sample expenses, plus income, bills and a debt and a loan.';
    } catch (error) {
      message = 'Could not add the sample data: $error';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const Icon(Icons.dataset_outlined),
        title: const Text('Add a month of sample data'),
        subtitle: Text(_busy ? 'Adding… $_done expenses saved' : 'Test expenses and budgets for last month and this month'),
        trailing: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _busy ? null : _run,
      ),
    );
  }
}
