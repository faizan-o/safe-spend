/// Names of the Firestore collections. All of a user's data lives under
/// users/{uid}, so one security rule protects everything:
///
/// users/{uid}                      profile and settings
///   categories/{categoryId}        spending categories
///   budgets/{monthKey}             the budget declared for a month
///   expenses/{expenseId}           individual expenses
///   monthStats/{monthKey}          running totals for a month
///   monthSummaries/{monthKey}      generated month-end reports
///   insights/{dayKey}              daily reminder suggestions
class FirestorePaths {
  const FirestorePaths._();

  static const users = 'users';
  static const categories = 'categories';
  static const budgets = 'budgets';
  static const expenses = 'expenses';
  static const monthStats = 'monthStats';
  static const monthSummaries = 'monthSummaries';
  static const insights = 'insights';
}
