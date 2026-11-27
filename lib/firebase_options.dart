// PLACEHOLDER. Running `flutterfire configure` in the project folder replaces
// this file with your real Firebase settings. Until then the app detects the
// "YOUR_" values below and uses the on-device demo sign-in instead.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: "AIzaSyBChNx4-09LDURmGW2LaX8QlV-C1pbwbB0",
      authDomain: "safespend-backend.firebaseapp.com",
      projectId: "safespend-backend",
      // storageBucket: "safespend-backend.firebasestorage.app",
      messagingSenderId: "739346237582",
      appId: "1:739346237582:web:4ba4e5ccf522125eafa1df",
    );
  }
}
