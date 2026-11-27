import 'map_readers.dart';

/// When (and whether) to send the daily reminder.
class ReminderSettings {
  const ReminderSettings({this.enabled = true, this.hour = 21, this.minute = 0});

  final bool enabled;
  final int hour;
  final int minute;

  factory ReminderSettings.fromMap(Map<String, dynamic> map) {
    return ReminderSettings(
      enabled: readBool(map, 'enabled', true),
      hour: readInt(map, 'hour', 21),
      minute: readInt(map, 'minute', 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
      };

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }
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
