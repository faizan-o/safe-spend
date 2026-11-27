import 'map_readers.dart';

/// Whether a category is overspending (red), saving (green) or on track.
enum FlagType { red, green, none }

/// How one category did over the month.
class CategoryResult {
  const CategoryResult({
    required this.categoryId,
    required this.name,
    required this.limit,
    required this.spent,
    this.flag = FlagType.none,
  });

  final String categoryId;
  final String name;
  final int limit;
  final int spent;
  final FlagType flag;

  /// Share of the limit that was used (1.0 = exactly on budget).
  double get usedRatio => limit > 0 ? spent / limit : 0;

  factory CategoryResult.fromMap(Map<String, dynamic> map) {
    return CategoryResult(
      categoryId: readString(map, 'categoryId'),
      name: readString(map, 'name'),
      limit: readInt(map, 'limit'),
      spent: readInt(map, 'spent'),
      flag: enumByName(FlagType.values, map['flag'], FlagType.none),
    );
  }

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'name': name,
        'limit': limit,
        'spent': spent,
        'flag': flag.name,
      };
}

/// One point in the written report: a category and what to know about it.
class ReportPoint {
  const ReportPoint({required this.title, required this.detail, this.categoryId});

  final String title;
  final String detail;
  final String? categoryId;

  factory ReportPoint.fromMap(Map<String, dynamic> map) => ReportPoint(
        title: readString(map, 'title'),
        detail: readString(map, 'detail'),
        categoryId: readStringOrNull(map, 'categoryId'),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'detail': detail,
        if (categoryId != null) 'categoryId': categoryId,
      };
}

/// An action the user can take next month.
class ReportAction {
  const ReportAction({required this.title, required this.action, this.estimatedSaving});

  final String title;
  final String action;

  /// Estimated saving per month in minor units, when the workflow gave one.
  final int? estimatedSaving;

  factory ReportAction.fromMap(Map<String, dynamic> map) => ReportAction(
        title: readString(map, 'title'),
        action: readString(map, 'action'),
        estimatedSaving: readIntOrNull(map, 'estimatedSaving'),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'action': action,
        if (estimatedSaving != null) 'estimatedSaving': estimatedSaving,
      };
}

/// The written part of the month-end report, produced by the n8n workflow.
class MonthReport {
  const MonthReport({
    this.headline = '',
    this.narrative = '',
    this.overspent = const [],
    this.saved = const [],
    this.improvements = const [],
    this.partial = false,
    this.generatedBy = '',
  });

  final String headline;

  /// A short paragraph (Markdown) explaining the month.
  final String narrative;

  /// Where the user spent more than planned or more than usual.
  final List<ReportPoint> overspent;

  /// Where the user saved.
  final List<ReportPoint> saved;
  final List<ReportAction> improvements;

  /// True when the month was not over yet when the report was made.
  final bool partial;

  /// "n8n" for the AI report, "rules" when the AI step was unavailable.
  final String generatedBy;

  factory MonthReport.fromMap(Map<String, dynamic> map) => MonthReport(
        headline: readString(map, 'headline'),
        narrative: readString(map, 'narrative'),
        overspent: readMapList(map, 'overspent').map(ReportPoint.fromMap).toList(),
        saved: readMapList(map, 'saved').map(ReportPoint.fromMap).toList(),
        improvements: readMapList(map, 'improvements').map(ReportAction.fromMap).toList(),
        partial: readBool(map, 'partial'),
        generatedBy: readString(map, 'generatedBy'),
      );

  Map<String, dynamic> toMap() => {
        'headline': headline,
        'narrative': narrative,
        'overspent': overspent.map((p) => p.toMap()).toList(),
        'saved': saved.map((p) => p.toMap()).toList(),
        'improvements': improvements.map((a) => a.toMap()).toList(),
        'partial': partial,
        'generatedBy': generatedBy,
      };
}

/// The generated report for a finished month.
/// Stored at users/{uid}/monthSummaries/{monthKey}.
class MonthSummary {
  const MonthSummary({
    required this.monthKey,
    required this.income,
    required this.totalSpent,
    required this.flexibleSpent,
    required this.saved,
    this.categories = const [],
    this.suggestion = '',
    this.report,
    this.generatedAt,
  });

  final String monthKey;
  final int income;
  final int totalSpent;
  final int flexibleSpent;

  /// Money left unspent from the flexible pool (can be negative).
  final int saved;
  final List<CategoryResult> categories;

  /// One suggestion for next month.
  final String suggestion;

  /// The written report. Null for summaries made without the n8n workflow.
  final MonthReport? report;
  final DateTime? generatedAt;

  List<CategoryResult> get redFlags =>
      categories.where((c) => c.flag == FlagType.red).toList();

  List<CategoryResult> get greenFlags =>
      categories.where((c) => c.flag == FlagType.green).toList();

  factory MonthSummary.fromMap(String monthKey, Map<String, dynamic> map) {
    return MonthSummary(
      monthKey: monthKey,
      income: readInt(map, 'income'),
      totalSpent: readInt(map, 'totalSpent'),
      flexibleSpent: readInt(map, 'flexibleSpent'),
      saved: readInt(map, 'saved'),
      categories: readMapList(map, 'categories').map(CategoryResult.fromMap).toList(),
      suggestion: readString(map, 'suggestion'),
      report: map['report'] is Map ? MonthReport.fromMap(readMap(map, 'report')) : null,
      generatedAt: readDate(map, 'generatedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'monthKey': monthKey,
        'income': income,
        'totalSpent': totalSpent,
        'flexibleSpent': flexibleSpent,
        'saved': saved,
        'categories': categories.map((c) => c.toMap()).toList(),
        'suggestion': suggestion,
        if (report != null) 'report': report!.toMap(),
      };
}
