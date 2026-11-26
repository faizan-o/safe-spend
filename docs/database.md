# SafeSpend database

Cloud Firestore, with everything stored under the signed-in user's own document.

## Layout

```
users/{uid}                      profile and settings              UserProfile
  categories/{categoryId}        spending categories               ExpenseCategory
  budgets/{monthKey}             budget declared for a month       MonthlyBudget
  expenses/{expenseId}           individual expenses               Expense
  monthStats/{monthKey}          running totals for a month        MonthStats
  monthSummaries/{monthKey}      generated month-end report        MonthSummary
  insights/{dayKey}              daily reminder suggestion         DailyInsight
```

`uid` is the Firebase Authentication user id. `monthKey` looks like `2026-11` and `dayKey` like
`2026-11-26`, both from the device's local date.

## How each feature is stored

| Feature | Where |
| --- | --- |
| Categorized budget declared at the start of the month | `budgets/{monthKey}`: income plus a list of category limits |
| Daily budget tracker (safe to spend today) | worked out from `budgets` and `monthStats`: `(flexiblePool - flexibleSpent) / days left` |
| Speech-to-text entry | an `expenses` document with `source: voice` and the original `transcript` |
| Red and green flags | worked out from `monthStats.spentByCategory` against the budget limits; saved in the summary |
| Daily reminder with suggestions | reminder time in `users/{uid}.reminder`; the suggestion text in `insights/{dayKey}` |
| Summary at the end of the month | `monthSummaries/{monthKey}` |

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
