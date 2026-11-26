import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/local_auth_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = await _createAuthService();
  runApp(SafeSpendApp(auth: auth));
}

/// Uses Firebase when `flutterfire configure` has been run, and the on-device
/// demo sign-in otherwise (or if Firebase cannot start on this platform).
Future<AuthService> _createAuthService() async {
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (!options.apiKey.startsWith('YOUR_')) {
      await Firebase.initializeApp(options: options);
      return FirebaseAuthService();
    }
  } catch (error) {
    debugPrint('Firebase unavailable, using demo sign-in: $error');
  }
  return LocalAuthService.create();
}

class SafeSpendApp extends StatelessWidget {
  const SafeSpendApp({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: AuthGate(auth: auth),
    );
  }
}
