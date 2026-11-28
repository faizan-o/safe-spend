import 'map_readers.dart';

/// What the app may remind the user about, and when.
///
/// [enabled], [hour] and [minute] are the daily "log your spending" reminder
/// (the first version only had that one). The rest switch the other kinds.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.hour = 21,
    this.minute = 0,
    this.bills = true,
    this.debts = true,
    this.budgetAlerts = true,
    this.dueHour = 9,
  });

  /// The daily reminder to log spending.
  final bool enabled;
  final int hour;
  final int minute;

  /// Bills and expected income that are coming due.
  final bool bills;

  /// Debts to repay and loans to collect that are coming due.
  final bool debts;

  /// A heads-up when a category reaches 90% of its limit, and when it goes over.
  final bool budgetAlerts;

  /// The hour of the day (0-23) reminders about due dates arrive.
  final int dueHour;

  factory ReminderSettings.fromMap(Map<String, dynamic> map) {
    return ReminderSettings(
      enabled: readBool(map, 'enabled', true),
      hour: readInt(map, 'hour', 21).clamp(0, 23).toInt(),
      minute: readInt(map, 'minute', 0).clamp(0, 59).toInt(),
      bills: readBool(map, 'bills', true),
      debts: readBool(map, 'debts', true),
      budgetAlerts: readBool(map, 'budgetAlerts', true),
      dueHour: readInt(map, 'dueHour', 9).clamp(0, 23).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'bills': bills,
        'debts': debts,
        'budgetAlerts': budgetAlerts,
        'dueHour': dueHour,
      };

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? bills,
    bool? debts,
    bool? budgetAlerts,
    int? dueHour,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      bills: bills ?? this.bills,
      debts: debts ?? this.debts,
      budgetAlerts: budgetAlerts ?? this.budgetAlerts,
      dueHour: dueHour ?? this.dueHour,
    );
  }

  /// True when any scheduled reminder is switched on.
  bool get anyScheduled => enabled || bills || debts;
}

/// The user's profile and settings. Stored at users/{uid}; the document id is
/// the Firebase Authentication uid.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.currencyCode = 'PKR',
    this.currencySymbol = 'Rs.',
    this.reminder = const ReminderSettings(),
    this.onboardingComplete = false,
    this.openingBalance = 0,
    this.openingBalanceDay,
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;
  final String currencyCode;
  final String currencySymbol;
  final ReminderSettings reminder;

  /// True once the user has finished first-time setup (their first budget).
  final bool onboardingComplete;

  /// The money the user had when they started using the app, in minor units,
  /// and the day ("yyyy-MM-dd") that number is true for. Everything recorded
  /// from that day on is added to it to get the current balance.
  final int openingBalance;
  final String? openingBalanceDay;
  final DateTime? createdAt;

  /// True once the user has entered an opening balance.
  bool get hasOpeningBalance => openingBalanceDay != null;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfile(
      uid: uid,
      name: readString(map, 'name'),
      email: readString(map, 'email'),
      currencyCode: readString(map, 'currencyCode', 'PKR'),
      currencySymbol: readString(map, 'currencySymbol', 'Rs.'),
      reminder: ReminderSettings.fromMap(readMap(map, 'reminder')),
      onboardingComplete: readBool(map, 'onboardingComplete'),
      openingBalance: readInt(map, 'openingBalance'),
      openingBalanceDay: readStringOrNull(map, 'openingBalanceDay'),
      createdAt: readDate(map, 'createdAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
        'reminder': reminder.toMap(),
        'onboardingComplete': onboardingComplete,
        if (openingBalanceDay != null) ...{
          'openingBalance': openingBalance,
          'openingBalanceDay': openingBalanceDay,
        },
      };
}
