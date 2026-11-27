# SafeSpend n8n workflows

Three importable workflows in `workflows/`. They read and write the same Firestore schema as the app
(`schema/safespend.schema.json`, mirrored by `lib/models`) and are **not yet connected to the app**.

| File | Webhook | What it does |
| --- | --- | --- |
| `safespend-voice-expense.json` | `POST /webhook/safespend/voice` | speech-to-text sentence → one expense → saved for the signed-in user |
| `safespend-receipt-scanner.json` | `POST /webhook/safespend/receipt` | photo/PDF of a receipt, bill or payment screenshot → expense (with line items) |
| `safespend-monthly-report.json` | `POST /webhook/safespend/report` + monthly schedule | month-end report: where you overspent, where you saved, what to improve |

## Setup (about 10 minutes)

1. **Firebase service account.** Firebase console → Project settings → Service accounts → Generate key.
   In n8n create a credential **Google Service Account API** with that JSON and scope
   `https://www.googleapis.com/auth/datastore`. Select it on every Firestore HTTP node
   (nodes marked with a credential warning after import).
2. **Gemini.** Get a key at https://aistudio.google.com/apikey (free tier available). In n8n create a credential **Header Auth**: name `x-goog-api-key`, value your key. Select it on the `Gemini` nodes.
3. **Config node** (first node after the trigger, in each workflow): set `projectId` and `firebaseApiKey`
   (the web API key in `firebase_options.dart`). Tunables: `model` (default `gemini-3.8-flash`; check AI Studio for current model names), `autoSaveMinConfidence` (0.8),
   `maxAutoSaveRupees` (100000), `defaultUtcOffsetMinutes` (300 = Pakistan).
4. Import the three files (Workflows → Import from file), activate them. Use the **Production** webhook URL in the app later.
5. n8n's default request limit is 16 MB; receipts are capped at 5 MB by the workflow.

## How they stay consistent with the app

- **Atomic writes.** Every saved expense is one Firestore `commit` containing the expense *and* the
  `monthStats/{monthKey}` increments (`totalSpent`, `flexibleSpent` only for flexible categories, `expenseCount`,
  `spentByCategory.<id>`, `spentByDay.<dd>`), exactly like `ExpenseRepository.addExpense`.
- **Money in paisa.** The workflows talk rupees to the app and store integer paisa.
- **Real categories.** They load the user's own non-archived categories from Firestore (falling back to the fixed-id
  defaults) and force the AI to choose from that list; unknown ids fall back to `other` and are sent for review.
- **Local dates.** Month/day keys come from `sentAt` + `timeZoneOffsetMinutes`, like the app. "Yesterday" is stored at local noon; future dates are clamped to now.
- **Receipts.** When a receipt is auto-saved, the same commit also sets `receipts/{receiptId}` to `status: saved` with the `expenseId`. The workflows never read the stored picture; the app sends the picture directly and keeps its own compressed copy in Firestore (`receiptImages`).
- **No duplicates.** The expense id is `voice_<clientRequestId>` / `receipt_<clientRequestId>` and written with
  `exists:false`, so a retried request returns `duplicate:true` instead of double-counting.
- **Security.** Every app call must carry `Authorization: Bearer <Firebase ID token>`; the workflow verifies it with Google,
  and uses the token's uid (a different `userId` in the body is rejected). The service account bypasses Firestore rules, so
  the workflows re-check what the rules would: positive integer amount, category, date, note ≤ 500. Transcript and receipt text
  are treated as untrusted data for the AI.
- **Auto-save vs review.** Saved only when `status=parsed`, confidence ≥ threshold, the category matched, amount ≤ limit,
  date sane and currency matches. Otherwise the parsed expense is returned with `needsReview:true` and `reviewReasons`
  and nothing is written. Send `"save": false` to always preview.

## Request / response

Voice request (what the app already sends works; `categories` is ignored because the workflow reads them from Firestore):
```json
{ "clientRequestId": "u1-173-1", "userId": "u1", "transcript": "spent 500 on lunch yesterday",
  "locale": "en_US", "sentAt": "2026-11-26T09:30:00.000Z", "timeZoneOffsetMinutes": 300, "save": true }
```
Receipt request: same fields plus an optional `"receiptId"` (the id of the receipt record the app created; the workflow links the saved expense to it) and `"imageBase64": "<base64>"` and `"mimeType": "image/jpeg"` (also png, webp, gif, application/pdf) instead of `transcript`.

Voice/receipt response:
```json
{ "workflow": "n8n-voice", "status": "parsed", "message": "Rs. 500 on lunch", "saved": true, "duplicate": false,
  "needsReview": false, "reviewReasons": [], "expenseId": "voice_u1-173-1", "confidence": 0.95,
  "expense": { "amount": 500, "categoryId": "food", "categoryName": "Food & dining", "note": "lunch",
               "merchant": null, "date": "2026-11-25", "items": [] } }
```
`status` is `parsed`, `needs_clarification` or `failed`. When `saved` is true the app must **not** save again;
when `needsReview` is true the app shows its review card and saves itself (`reviewReasons` explains why).
HTTP codes: 400 bad request, 401 bad token, 403 other user's id, 413 file too big, 502/503 AI unavailable.

Report request: `{ "monthKey": "2026-10", "force": true }` (both optional; default = current month, flagged `partial`).
Response: `{ "status": "generated|skipped|failed", "monthKey", "summary": { ...MonthSummary incl. report } }`.
The monthly schedule runs at 03:00 on the 1st for the month that just ended, for every user, and never overwrites an existing report.
The report is stored in `monthSummaries/{monthKey}` (`MonthSummary` + `report`: headline, narrative, overspent, saved, improvements). Numbers
(flags, totals, saved) are computed in code with the app's thresholds; the AI only writes the words, and a rules-based
report is written if the AI is unavailable (`generatedBy: "rules"`).
It also recomputes totals from the expenses and reports `statsDrift` if `monthStats` disagrees.

## Developing

- Workflows are generated: edit `src/*.js` or `build.py`, then `python3 n8n/build.py`.
- `node n8n/test/run_tests.js` runs all three workflows in a small n8n emulator with mocked HTTP (30 checks).
- `flutter test test/n8n_schema_test.dart` fails if the Dart models and `schema/safespend.schema.json` drift apart.
- Not tested against a live n8n/Firestore/Gemini account. First run: send a curl and look at the executions.

```bash
curl -X POST "$N8N/webhook-test/safespend/voice" -H "Authorization: Bearer $ID_TOKEN" -H 'Content-Type: application/json' \
  -d '{"clientRequestId":"t1","transcript":"spent 500 on lunch","sentAt":"'$(date -u +%FT%TZ)'","timeZoneOffsetMinutes":300}'
```

Note: on Google's free Gemini tier, prompts may be used to improve Google's products and rate limits are low. For real users' financial data, use a paid (billing-enabled) key.

## Skip the manual setup (optional)

Copy `local.config.example.json` to `local.config.json`, fill it in and run `python3 build.py`. The generated workflow files then already contain
your `projectId`, Firebase web API key and (if you give `geminiApiKey`) the Gemini key, so there is nothing to type into n8n after importing.
The Google service-account credential for Firestore still has to exist in n8n (add its id as `googleCredentialId`). `local.config.json` is
git-ignored; the generated files contain your keys, so do not publish them.
