import 'map_readers.dart';

/// The suggestion shown in a day's reminder.
/// Stored at users/{uid}/insights/{dayKey}, for example insights/2026-11-26.
class DailyInsight {
  const DailyInsight({
    required this.dayKey,
    required this.message,
    this.predictedSpend,
    this.safeToSpend,
    this.createdAt,
  });

  final String dayKey;

  /// The text of the reminder, e.g. "Fridays are your biggest food days."
  final String message;

  /// Predicted spending for the day, in minor units.
  final int? predictedSpend;

  /// The safe-to-spend figure the reminder was based on, in minor units.
  final int? safeToSpend;
  final DateTime? createdAt;

  factory DailyInsight.fromMap(String dayKey, Map<String, dynamic> map) {
    return DailyInsight(
      dayKey: dayKey,
      message: readString(map, 'message'),
      predictedSpend: readIntOrNull(map, 'predictedSpend'),
      safeToSpend: readIntOrNull(map, 'safeToSpend'),
      createdAt: readDate(map, 'createdAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'dayKey': dayKey,
        'message': message,
        'predictedSpend': predictedSpend,
        'safeToSpend': safeToSpend,
      };
}
