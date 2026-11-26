import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/data_scope.dart';
import 'main_shell.dart';

/// The screen shown after signing in. It opens on voice input, with the
/// dashboard one tap away, when a database is available, and shows an
/// explanation in demo mode (which has no database).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.auth, required this.user});

  final AuthService auth;
  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final data = DataScope.maybeOf(context);
    if (data == null) return _DemoModeScreen(auth: auth, user: user);
    return MainShell(auth: auth, user: user, data: data);
  }
}

class _DemoModeScreen extends StatelessWidget {
  const _DemoModeScreen({required this.auth, required this.user});

  final AuthService auth;
  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Hi, ${user.firstName}',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'The dashboard stores your budget and expenses in Firebase, and this '
                  'build is running in demo mode without it.\n\n'
                  'Run flutterfire configure, set up Firestore (see docs/database.md) '
                  'and restart the app.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
