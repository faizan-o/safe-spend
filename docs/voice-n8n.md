# Connecting the app to the n8n workflows

The app talks to three n8n workflows (see `n8n/README.md` to import and set them up):

| Feature | App code | Webhook |
| --- | --- | --- |
| Voice / typed expense | `lib/voice/voice_workflow_client.dart` | `POST <base>/safespend/voice` |
| Receipt photo | `lib/voice/receipt_client.dart` | `POST <base>/safespend/receipt` |
| Monthly report | `lib/report/report_client.dart` | `POST <base>/safespend/report` |

## Turning it on

Run or build the app with the base of your n8n **production** webhook URL (the part before `/safespend/...`):

```bash
flutter run --dart-define=N8N_BASE_URL=https://YOUR-N8N-HOST/webhook
flutter build apk --dart-define=N8N_BASE_URL=https://YOUR-N8N-HOST/webhook
```

Without `N8N_BASE_URL` the app uses built-in dummy workflows (a "Test mode" chip is shown) so you can try the screens;
month reports are then unavailable. Every call carries the signed-in user's Firebase ID token
(`Authorization: Bearer ...`), which the workflows verify.

## What the app does with an answer

- `saved: true` — n8n already stored the expense and updated the month totals. The app shows "Saved ..." and does **not** save again.
- `needsReview: true` — n8n was not sure and wrote nothing. The app shows the review card (with the reason), and the user
  saves, edits or discards. The app then writes it itself (`source: voice` or `receipt`).
- `needs_clarification` / `failed` — a message and a "Try again" button.
- Errors (offline, timeout, 401, 5xx) — a readable message; the typed box and manual "Add expense" always still work.

## Using it

- **Voice:** the app opens on the Voice tab. Tap the mic, speak, or type.
- **Receipts:** "Scan a receipt" (Voice tab, or the button on the Receipts tab) takes a photo or picks one from the gallery (compressed to about 1800 px, JPEG).
  The picture is compressed and kept in Firestore, and listed with its timestamp on the **Receipts** tab. On Android/iOS you can take a photo or upload one; on desktop and web you can only upload a file.
- **Reports:** Dashboard menu → *Monthly report*. It shows the report n8n wrote to `monthSummaries/{monthKey}`, and
  *Generate / Refresh report* asks n8n to rebuild it. n8n also creates last month's report for everyone on the 1st at 03:00.

## Platform setup

**Android** (`android/app/src/main/AndroidManifest.xml`, inside `<manifest>`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<queries><intent><action android:name="android.speech.RecognitionService"/></intent></queries>
```
The camera and gallery need no extra Android permission (image_picker uses the system picker/camera app).

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSSpeechRecognitionUsageDescription</key><string>SafeSpend turns what you say into an expense.</string>
<key>NSMicrophoneUsageDescription</key><string>SafeSpend listens when you tap the microphone.</string>
<key>NSCameraUsageDescription</key><string>SafeSpend reads receipts you photograph.</string>
<key>NSPhotoLibraryUsageDescription</key><string>SafeSpend reads receipts you choose.</string>
```
Emulators often lack a speech service; use the typed box or the example chips there.

## Contract

The exact request/response JSON is in `n8n/README.md`.

## Voice for everything, not only expenses

The voice workflow (`/webhook/safespend/voice`) now also understands income, bills, debts, loans, repayments and the opening balance. The model returns an `intent`; for anything other than `expense` the answer has no `expense` and carries an `entry` instead:

```json
{ "status": "parsed", "intent": "bill", "needsReview": true, "reviewReasons": ["other_entry"], "saved": false,
  "entry": { "type": "bill", "amount": 25000, "title": "rent", "categoryId": "rent",
             "frequency": "monthly", "dueDate": "2026-12-01", "note": null } }
```

`entry.type` is `income`, `bill`, `bill_paid` (a bill that already exists was paid: the app opens its "mark paid" sheet), `budget` (total for a week, month or year: the app confirms, then changes or starts that budget), `category_budget` (one category's limit in the budget covering today: the app confirms, then saves), `debt` (I borrowed), `loan` (I lent), `repayment` or `opening_balance`. Other fields: `source` (income), `title`, `frequency`, `dueDate`, `person`, `date`, `note`. Nothing is written by the workflow for these: the app opens the normal form pre-filled ("Review and save") and saves through its own repositories, so month totals and balances stay correct. Names and notes that were not actually said are dropped. After changing the workflow, re-import `safespend-voice-expense.json` in n8n.
