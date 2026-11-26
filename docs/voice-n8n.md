# Voice input and the n8n workflow

Flow: **speak → speech-to-text (on device) → n8n webhook → review card → app saves the expense.**
n8n only *parses*; the app writes to Firestore, so monthly stats stay consistent.

## Running

- Without a webhook the built-in **dummy** answers (test mode, shown as a chip on the card).
- With n8n: `flutter run --dart-define=N8N_WEBHOOK_URL=https://your-n8n/webhook/safespend-voice`
- The user's Firebase ID token is sent as `Authorization: Bearer <token>`. The workflow should verify it
  (Google's `securetoken` public keys, audience = your Firebase project ID) and that `userId` matches the token's `sub`.

## Request (POST, JSON)

```json
{
  "clientRequestId": "u1-1732631400000-1",
  "userId": "u1",
  "source": "voice",
  "transcript": "spent 500 on lunch yesterday",
  "locale": "en_US",
  "sentAt": "2026-11-26T09:30:00.000Z",
  "localDate": "2026-11-26",
  "timeZoneOffsetMinutes": 300,
  "currency": { "code": "PKR", "symbol": "Rs." },
  "categories": [ { "id": "food", "name": "Food", "kind": "flexible" } ]
}
```

## Response (JSON; a one-item list is also accepted)

```json
{
  "status": "parsed",
  "message": "Rs. 500 on Food",
  "expense": { "amount": 500, "categoryId": "food", "categoryName": "Food",
               "note": "lunch", "date": "2026-11-25" },
  "confidence": 0.93,
  "workflow": "n8n"
}
```

- `status`: `parsed` | `needs_clarification` | `failed`.
- `amount` is in **rupees** (the app converts to paisa). `categoryId` must be one of the sent ids.
- `date`: `yyyy-MM-dd` (day only) or full ISO time; omitted = now. Future dates are clamped to now.

## Platform setup

**Android** (`AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<queries><intent><action android:name="android.speech.RecognitionService"/></intent></queries>
```
**iOS** (`Info.plist`): `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription`.

Emulators often lack a speech service; use the typed box or example chips there.
