import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/local_auth_service.dart';
import 'theme.dart';

typedef _Backend = ({AuthService auth, AppDatabase? database});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backend = await _startBackend();
  runApp(SafeSpendApp(auth: backend.auth, database: backend.database));
}

/// Uses Firebase (sign-in and Firestore) when `flutterfire configure` has been
/// run, and the on-device demo sign-in otherwise (or if Firebase cannot start
/// on this platform). Demo mode has no database.
Future<_Backend> _startBackend() async {
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (!options.apiKey.startsWith('YOUR_')) {
      await Firebase.initializeApp(options: options);
      AppDatabase.configure();
      return (auth: FirebaseAuthService(), database: AppDatabase());
    }
  } catch (error) {
    debugPrint('Firebase unavailable, using demo sign-in: $error');
  }
  return (auth: await LocalAuthService.create(), database: null);
}

class SafeSpendApp extends StatelessWidget {
  const SafeSpendApp({super.key, required this.auth, this.database});

  final AuthService auth;
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: AuthGate(auth: auth, database: database),
    );
  }
}
