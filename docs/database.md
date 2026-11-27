# SafeSpend database

Cloud Firestore, with everything stored under the signed-in user's own document.

## Layout

```
users/{uid}                      profile and settings              UserProfile
  categories/{categoryId}        spending categories               ExpenseCategory
  budgets/{budgetId}             a budget for any period           MonthlyBudget
  expenses/{expenseId}           individual expenses               Expense
  incomes/{incomeId}             money received                    Income
  recurring/{recurringId}        bills, rent, fees, expected pay   RecurringItem
  debts/{debtId}                 money I owe / money I lent        Debt
  monthStats/{monthKey}          running totals for a month        MonthStats
  monthSummaries/{monthKey}      generated month-end report        MonthSummary
  insights/{dayKey}              daily reminder suggestion         DailyInsight
  receipts/{receiptId}           a scanned receipt                 Receipt
```

Receipt pictures are compressed JPEGs in Firestore at `users/{uid}/receiptImages/{receiptId}` (a `Blob`, at most about 700 KB so it fits the 1 MiB document limit). The `receipts` record keeps a ~200 px thumbnail for the list.

`uid` is the Firebase Authentication user id. `monthKey` looks like `2026-11` and `dayKey` like
`2026-11-26`, both from the device's local date.

## How each feature is stored

| Feature | Where |
| --- | --- |
| Categorized budget declared at the start of the month | `budgets/{monthKey}`: income plus a list of category limits |
| Opening balance | `users/{uid}.openingBalance` and `openingBalanceDay` (the day it is true for) |
| Budget for a week, month, year or custom dates | `budgets/{budgetId}`: `periodType`, `startDay`, `endDay`, `income` (the money budgeted), category limits. Old documents without dates mean the calendar month of `monthKey` (the id is the month key for those) |
| Income | `incomes/{incomeId}`; totals kept in `monthStats` (`totalIncome`, `incomeByDay`) in the same atomic batch |
| Bills, rent, fees with due dates | `recurring/{id}`: `frequency`, `interval`, `nextDueDay`, `endDay`, `remindDays`, `autoRecord`. Paying one writes an `expenses`/`incomes` document with `recurringId` and a deterministic id (`rec_{id}_{dueDay}`), so a due date can never be recorded twice |
| Debts and loans | `debts/{id}`: `direction` (`owedByMe` / `owedToMe`), `person`, `amount`, `dueDay`, `payments[]`, `affectsBalance` |
| Current balance | not stored: `openingBalance + income - spending +/- debt movements`, worked out on the device from `monthStats` and `debts` |
| Daily budget tracker (safe to spend today) | worked out from `budgets` and `monthStats`: `(flexiblePool - flexibleSpent) / days left` |
| Speech-to-text entry | an `expenses` document with `source: voice` and the original `transcript` |
| Receipt photo | a `receiptImages` document, a `receipts` record (status, time, what was read) and an `expenses` document with `source: receipt`, `receiptId`, `merchant` and `items` |
| Red and green flags | worked out from `monthStats.spentByCategory` against the budget limits; saved in the summary |
| Daily reminder with suggestions | reminder time in `users/{uid}.reminder`; the suggestion text in `insights/{dayKey}` |
| Summary at the end of the month | `monthSummaries/{monthKey}`: totals and flags, plus the written `report` |

## Decisions worth knowing

- **Money is an integer in paisa** (Rs. 1 = 100). No decimals are stored, so totals are exact. Use
  `Money.parse` for what the user types or says and `Money.format` for display.
- **Totals are stored, not recomputed.** Every expense add, edit or delete updates
  `monthStats/{monthKey}` in the same atomic batch, so the home screen reads one small document instead of
  every expense. If the totals ever look wrong, `expenses.rebuildStats(monthKey)` recomputes them.
- **Only flexible categories feed the daily number.** Categories have a kind: `fixed` (rent, bills,
  committee), `flexible` (everyday) or `savings`. `flexiblePool = income - fixed - savings`, and
  `flexibleSpent` counts only flexible expenses, so paying rent does not shrink the daily number twice.
- **Snapshots keep history correct.** An expense stores its category name and kind, and a budget stores each
  category's name, icon and color, so renaming or archiving a category never changes past months.
  Categories are archived, never deleted.
- **Works offline.** Local persistence is on. Writes show up in the app immediately and sync later; their
  Futures complete only once the server confirms, so don't make a screen wait on them while offline.
- **Editing an expense needs the old version.** `updateExpense(previous:, updated:)` and `deleteExpense`
  use the old values to adjust the totals without a server read, which is what keeps them working offline.
- **Time zones.** Months and days follow the device's local time. Travelling across time zones can shift an
  expense near midnight into the neighbouring day.

## Using it from a screen

```dart
final data = DataScope.of(context);

// declare this month's budget
await data.budgets.saveBudget(MonthlyBudget(
  monthKey: DateKeys.ofMonth(DateTime.now()),
  income: Money.fromMajor(60000),
  categories: [CategoryBudget.fromCategory(rent, Money.fromMajor(25000)), ...],
));

// log an expense
await data.expenses.addExpense(Expense(
  amount: Money.fromMajor(500),
  categoryId: food.id, categoryName: food.name, categoryKind: food.kind,
  date: DateTime.now(),
));

// live numbers for the home screen
data.budgets.watchBudget(monthKey);
data.expenses.watchStats(monthKey);
```

`DataScope.of` throws in demo mode, because demo mode has no database. Use `DataScope.maybeOf` if a
screen must also work there.

## Setup

1. In the Firebase console, open **Build > Firestore Database > Create database**. Choose production mode
   and a region close to your users.
2. Add Firestore to `firebase.json` (keep the `flutter` section that `flutterfire configure` wrote):
   ```json
   "firestore": {
     "rules": "firestore.rules",
     "indexes": "firestore.indexes.json"
   }
   ```
3. Deploy the rules and the index:
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase deploy --only firestore
   ```
   Without the rules, production mode rejects every request. Do not use test mode.
4. `flutter pub get`, then run the app. The first sign-in creates `users/{uid}` and the default categories.

## n8n workflows

Voice, receipt and month-end report workflows (see `n8n/README.md`) write to the same collections as the app.
They use `n8n/schema/safespend.schema.json`, which `test/n8n_schema_test.dart` keeps in sync with the Dart models.
Extra optional expense fields written by them: `merchant`, `confidence`, `requestId` (the expense id is derived from it, which
prevents duplicates) and `items` (receipt lines). The security rules need no change: they validate only the required fields.

## Receipts in Firestore

1. The app shrinks the picture (about 1600 px, JPEG), stores it in `receiptImages/{id}`, and creates `receipts/{id}` (status `processing`, `hasImage`, `thumbnail`, `capturedAt`, `uploadedAt`) in one batch.
2. It sends the picture and the `receiptId` to the n8n receipt workflow. When the workflow auto-saves the expense it
   also sets the receipt to `saved` with the `expenseId`, in the same atomic commit. Otherwise the app records the result
   (`needsReview`, `failed`) and, when the user saves or discards, `saved` or `discarded`.
3. The Receipts tab lists them newest first with the thumbnail and time; tapping one loads the full picture.

**Camera vs upload:** on Android and iOS the user can take a photo or pick one; on desktop and web they can only upload a file.

**Setup:** nothing beyond `firebase deploy --only firestore` (the rules now include `receiptImages`). No Storage bucket or Blaze plan is needed.
Pictures that cannot be shrunk under the limit (for example a PDF) are still read by the workflow but are not kept.

## Balance, periods and recurring items

- All money is whole minor units (paisa). Day keys are `yyyy-MM-dd`, month keys `yyyy-MM`.
- The balance counts only what happened from `openingBalanceDay` on. For that day's month the per-day totals in `monthStats` are used.
- A budget's period is both ends included (a week is Monday to Sunday). Spending for the budget is read from `expenses` by `dayKey` range, so any period works; a yearly budget therefore reads that year's expenses.
- Several budgets can cover today at once (for example a monthly and a weekly one); the dashboard shows one and offers chips to switch.
- Recurring items with **Record it automatically** are recorded when the app opens or resumes, including dates missed while it was closed (up to 60 per item). There are no push notifications: due dates are shown in the app (Bills tab and dashboard).
- Editing an expense or income updates its month totals atomically (old amounts out, new in), also when the date moves to another month.
- The monthly report (n8n) is built from `monthStats` and the budget of that calendar month, so it exists for calendar-month budgets only. Income is shown in the app but is not read by the n8n workflows; voice and receipt entry create expenses only.
