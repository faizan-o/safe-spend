import 'dart:ui' show PointerDeviceKind;

import 'package:firebase_core/firebase_core.dart';

import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/local_auth_service.dart';
import 'settings/theme_controller.dart';
import 'theme.dart';

typedef _Backend = ({AuthService auth, AppDatabase? database});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  final backend = await _startBackend();
  runApp(SafeSpendApp(auth: backend.auth, database: backend.database));
}

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
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeController.mode,
        scrollBehavior: const _AppScrollBehavior(),
        home: AuthGate(auth: auth, database: database),
      ),
    );
  }
}

/// Lets lists be dragged with a mouse or trackpad too (the default only
/// allows touch), so the web and desktop builds feel the same as the phone.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
