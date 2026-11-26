// PLACEHOLDER. Running `flutterfire configure` in the project folder replaces
// this file with your real Firebase settings. Until then the app detects the
// "YOUR_" values below and uses the on-device demo sign-in instead.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'YOUR_API_KEY',
      appId: 'YOUR_APP_ID',
      messagingSenderId: 'YOUR_SENDER_ID',
      projectId: 'YOUR_PROJECT_ID',
    );
  }
}
