import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../services/auth_service.dart';
import '../widgets/data_scope.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';

/// Shows the home screen when signed in and the welcome screen otherwise,
/// and switches automatically when the sign-in state changes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, this.database});

  final AuthService auth;

  /// Null in demo mode, where there is no Firestore.
  final AppDatabase? database;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthUser?> _changes = widget.auth.authStateChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: _changes,
      initialData: widget.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user != null) {
          return SessionBootstrap(
            key: ValueKey(user.uid),
            database: widget.database,
            user: user,
            child: HomeScreen(auth: widget.auth, user: user),
          );
        }
        return WelcomeScreen(auth: widget.auth);
      },
    );
  }
}
