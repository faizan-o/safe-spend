# SafeSpend

Monthly finance manager that shows one daily safe-to-spend number.
Voice and receipt expense entry, a safe-to-spend dashboard, and AI month-end reports.

Features: opening balance and a live balance; budgets for a week, month, year or custom dates (several at once); income as well as expenses; bills, rent and fees with due dates, reminders and optional automatic recording; debts and loans with repayments and due dates; and editing of every expense, income, receipt and its items. Sign-in uses Firebase; the AI parts run in n8n with Gemini.

## Run it

This folder holds the Dart code only. Generate the Android/iOS platform folders once, then run:

```bash
cd safespend
flutter create . --project-name safespend --platforms=android,ios
flutter pub get
flutter run --dart-define=N8N_BASE_URL=https://YOUR-N8N-HOST/webhook   # leave the define out to use dummy voice/receipt
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
  main.dart, theme.dart, firebase_options.dart
  config/voice_config.dart        n8n address (N8N_BASE_URL)
  services/                       sign-in (Firebase or on-device demo)
  models/, data/                  Firestore schema and repositories (docs/database.md)
  logic/                          budget maths and the dashboard controller
  voice/                          speech-to-text, voice + receipt workflow clients, VoiceController
  report/report_client.dart       asks n8n to (re)build a month report
  screens/
    auth_gate / welcome / sign_in / sign_up / forgot_password
    main_shell.dart               tabs: Voice (default), Dashboard, Bills, Debts, Receipts
    receipts_screen.dart          timestamped receipts and receipt detail
    voice_screen.dart             speak, type or scan a receipt
    dashboard_screen.dart         safe-to-spend, flags, progress, expenses
    budget_setup / budgets / transactions / bills / debts / report screens
  widgets/                        shared UI
n8n/                              importable workflows, schema, README, local tests
docs/                             database.md, voice-n8n.md
firestore.rules, firestore.indexes.json
```

## Docs

- [docs/database.md](docs/database.md): Firestore schema, rules, setup.
- [n8n/README.md](n8n/README.md): import the 3 workflows, credentials (Firebase service account + Gemini key), contracts.
- [docs/voice-n8n.md](docs/voice-n8n.md): turning the app's n8n connection on, platform permissions (microphone, camera).

## Checklist to go live

1. Firebase: Auth + Firestore (no Storage and no paid plan needed), `flutterfire configure`, then `firebase deploy --only firestore`.
2. n8n: import and activate the workflows, add credentials, edit each Config node.
3. Run with `--dart-define=N8N_BASE_URL=.../webhook`; add the Android/iOS permissions from docs/voice-n8n.md.
4. `flutter analyze` and `flutter test`.
