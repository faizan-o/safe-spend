import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../settings/theme_controller.dart';
import '../theme.dart';
import '../utils/responsive.dart';

void openSettings(BuildContext context, AuthService auth, AuthUser user) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SettingsScreen(auth: auth, user: user)),
  );
}

/// App settings. Today: the appearance (light, dark or follow the device).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.auth, required this.user});

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
          const SizedBox(height: 24),
          Center(
            child: Text(AppConfig.appName, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
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
