// PLACEHOLDER. Running `flutterfire configure` in the project folder replaces
// this file with your real Firebase settings. Until then the app detects the
// "YOUR_" values below and uses the on-device demo sign-in instead.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBChNx4-09LDURmGW2LaX8QlV-C1pbwbB0',
      appId: '1:739346237582:android:b3fbe2ad35a73ff0afa1df',
      authDomain: "safespend-backend.firebaseapp.com",
      messagingSenderId: '739346237582',
      projectId: 'safespend-backend',
    );
  }
}
