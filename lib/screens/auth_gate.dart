import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';

/// Shows the home screen when signed in and the welcome screen otherwise,
/// and switches automatically when the sign-in state changes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth});

  final AuthService auth;

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
          return HomeScreen(auth: widget.auth, user: user);
        }
        return WelcomeScreen(auth: widget.auth);
      },
    );
  }
}
