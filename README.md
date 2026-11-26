# SafeSpend

Monthly finance manager that shows one daily safe-to-spend number.
This first step contains the startup UI and authentication.

## Run it

This folder holds the Dart code only. Generate the Android/iOS platform folders once, then run:

```bash
cd safespend
flutter create . --project-name safespend --platforms=android,ios
flutter pub get
flutter run
```

`flutter create .` keeps the existing `lib/`, `pubspec.yaml` and `test/` files. If it overwrites
`pubspec.yaml`, restore the dependencies listed in the copy you downloaded.

With no further setup the app runs in **demo mode**: accounts are stored on the device only, so you
can try sign up, sign in, sign out and password reset right away.

## Switch to real accounts (Firebase)

1. Create a project at https://console.firebase.google.com and, under Authentication, enable the
   **Email/Password** provider.
2. Install the tools and link the project:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   This overwrites `lib/firebase_options.dart` with your real settings. The app detects it and
   switches from demo mode to Firebase automatically.
3. On Android, Firebase needs `minSdk` 23 or higher: in `android/app/build.gradle(.kts)` set
   `minSdk = 23` (or `minSdkVersion 23`).

## Turn on Google sign-in

"Continue with Google" appears on the sign-in and sign-up screens. In demo mode, tapping it shows a
message that Firebase is needed; it signs in for real once Firebase is configured. It uses Firebase's built-in Google provider, so no extra Flutter package is needed.

1. Firebase console > Authentication > Sign-in method > enable **Google** and pick a support email.
2. **Android:** add your debug SHA-1 and SHA-256 fingerprints in Project settings > Your apps, then
   run `flutterfire configure` again so the config is refreshed. Get the fingerprints with:
   ```bash
   cd android && ./gradlew signingReport
   ```
   Add the release fingerprints too before publishing.
3. **iOS:** after `flutterfire configure`, open `ios/Runner/Info.plist` and add a URL scheme whose value is
   the `REVERSED_CLIENT_ID` from `ios/Runner/GoogleService-Info.plist`:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array><string>YOUR_REVERSED_CLIENT_ID</string></array>
     </dict>
   </array>
   ```
4. If an email already has a password account, Google sign-in for that email shows a message asking
   the user to sign in with their password (Firebase's default account-linking setting).

## Structure

```
lib/
  main.dart                       picks Firebase or demo sign-in, starts the app
  theme.dart                      colors, input and button styles, app name
  firebase_options.dart           placeholder, replaced by flutterfire configure
  services/
    auth_service.dart             interface the screens use (backend-independent)
    firebase_auth_service.dart    real accounts via Firebase Authentication
    local_auth_service.dart       on-device demo accounts
  screens/
    auth_gate.dart                signed in -> home, signed out -> welcome
    welcome_screen.dart           first screen: Create account / Sign in
    sign_up_screen.dart           name, email, password, confirm password
    sign_in_screen.dart           email, password, forgot password link
    forgot_password_screen.dart   sends a reset link
    home_screen.dart              placeholder shown after sign-in
  widgets/auth_widgets.dart       shared fields, button and message banner
  utils/validators.dart           form validation rules
test/validators_test.dart         unit tests for the validators
```

## Database

Data is stored in Cloud Firestore under `users/{uid}`. The schema, the decisions behind it, usage
examples and the Firebase setup steps are in [docs/database.md](docs/database.md). Security rules are
in `firestore.rules`.

## Next steps

1. Monthly budget setup (income, fixed bills, category budgets) and storage in Cloud Firestore
2. Expense entry (text first, then voice) and the daily safe-to-spend calculation
3. Red and green flags, daily reminder, month-end summary
