import 'food_analysis_result.dart';

enum NutritionDayType { training, rest }

enum NutritionReportSubmissionType { manual, automatic }

class DailyNutritionMetadata {
  const DailyNutritionMetadata({
    required this.dateKey,
    required this.dayType,
    required this.targetCalories,
  });

  final String dateKey;
  final NutritionDayType dayType;
  final int? targetCalories;

  Map<String, dynamic> toJson() => {
    'dateKey': dateKey,
    'dayType': dayType.name,
    'targetCalories': targetCalories,
  };

  factory DailyNutritionMetadata.fromJson(Map<String, dynamic> json) =>
      DailyNutritionMetadata(
        dateKey: _stringValue(json['dateKey']),
        dayType: NutritionDayType.values.firstWhere(
          (value) => value.name == json['dayType'],
          orElse: () => NutritionDayType.rest,
        ),
        targetCalories: _numValue(json['targetCalories'])?.toInt(),
      );
}

class DailyNutritionEntry {
  const DailyNutritionEntry({
    required this.id,
    required this.dateKey,
    required this.createdAt,
    required this.originalInput,
    required this.foodName,
    required this.quantityText,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    required this.isEstimated,
    this.confidence = 'medium',
    this.assumptions = const [],
    this.warnings = const [],
    this.consumedGrams,
    this.sourceType = FoodSourceType.local,
    this.sourceLabel = 'داده ذخیره‌شده',
    this.fdcId,
  });

  final String id;
  final String dateKey;
  final DateTime createdAt;
  final String originalInput;
  final String foodName;
  final String quantityText;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final bool isEstimated;
  final String confidence;
  final List<String> assumptions;
  final List<String> warnings;
  final double? consumedGrams;
  final FoodSourceType sourceType;
  final String sourceLabel;
  final int? fdcId;

  factory DailyNutritionEntry.fromAnalysis({
    required FoodAnalysisResult result,
    required String dateKey,
    DateTime? createdAt,
  }) {
    final timestamp = createdAt ?? DateTime.now();
    return DailyNutritionEntry(
      id: 'food-${timestamp.microsecondsSinceEpoch}',
      dateKey: dateKey,
      createdAt: timestamp,
      originalInput: result.originalInput,
      foodName: result.foodName,
      quantityText: result.quantityText,
      calories: result.calories,
      proteinGrams: result.proteinGrams,
      carbsGrams: result.carbsGrams,
      fatGrams: result.fatGrams,
      isEstimated: result.isEstimated,
      confidence: result.confidence,
      assumptions: result.assumptions,
      warnings: result.warnings,
      consumedGrams: result.consumedGrams,
      sourceType: result.sourceType,
      sourceLabel: result.sourceLabel,
      fdcId: result.fdcId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'dateKey': dateKey,
    'createdAt': createdAt.toIso8601String(),
    'originalInput': originalInput,
    'foodName': foodName,
    'quantityText': quantityText,
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'fatGrams': fatGrams,
    'isEstimated': isEstimated,
    'confidence': confidence,
    'assumptions': assumptions,
    'warnings': warnings,
    'consumedGrams': consumedGrams,
    'sourceType': sourceType.name,
    'sourceLabel': sourceLabel,
    'fdcId': fdcId,
  };

  factory DailyNutritionEntry.fromJson(Map<String, dynamic> json) {
    return DailyNutritionEntry(
      id: _stringValue(json['id']),
      dateKey: _stringValue(json['dateKey']),
      createdAt:
          DateTime.tryParse(_stringValue(json['createdAt'])) ?? DateTime.now(),
      originalInput: _stringValue(json['originalInput']),
      foodName: _stringValue(json['foodName']),
      quantityText: _stringValue(json['quantityText']),
      calories: _numValue(json['calories'])?.toDouble() ?? 0,
      proteinGrams: _numValue(json['proteinGrams'])?.toDouble() ?? 0,
      carbsGrams: _numValue(json['carbsGrams'])?.toDouble() ?? 0,
      fatGrams: _numValue(json['fatGrams'])?.toDouble() ?? 0,
      isEstimated: json['isEstimated'] is bool
          ? json['isEstimated'] as bool
          : true,
      confidence: json['confidence'] is String
          ? json['confidence'] as String
          : 'medium',
      assumptions: _listValue(
        json['assumptions'],
      ).whereType<String>().toList(growable: false),
      warnings: _listValue(
        json['warnings'],
      ).whereType<String>().toList(growable: false),
      consumedGrams: _numValue(json['consumedGrams'])?.toDouble(),
      sourceType: FoodSourceType.values.firstWhere(
        (value) => value.name == json['sourceType'],
        orElse: () => FoodSourceType.local,
      ),
      sourceLabel: json['sourceLabel'] is String
          ? json['sourceLabel'] as String
          : 'داده ذخیره‌شده',
      fdcId: _numValue(json['fdcId'])?.toInt(),
    );
  }
}

class DailyNutritionTotals {
  const DailyNutritionTotals({
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  const DailyNutritionTotals.zero()
    : calories = 0,
      proteinGrams = 0,
      carbsGrams = 0,
      fatGrams = 0;

  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;

  factory DailyNutritionTotals.fromEntries(
    Iterable<DailyNutritionEntry> entries,
  ) {
    var calories = 0.0;
    var protein = 0.0;
    var carbs = 0.0;
    var fat = 0.0;
    for (final entry in entries) {
      calories += entry.calories;
      protein += entry.proteinGrams;
      carbs += entry.carbsGrams;
      fat += entry.fatGrams;
    }
    return DailyNutritionTotals(
      calories: calories,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
    );
  }
}

class DailyNutritionReport {
  const DailyNutritionReport({
    required this.dateKey,
    required this.submittedAt,
    required this.entries,
    required this.totalCalories,
    required this.totalProteinGrams,
    required this.totalCarbsGrams,
    required this.totalFatGrams,
    required this.dayType,
    this.submissionType = NutritionReportSubmissionType.manual,
    this.targetCalories,
  });

  final String dateKey;
  final DateTime submittedAt;
  final List<DailyNutritionEntry> entries;
  final double totalCalories;
  final double totalProteinGrams;
  final double totalCarbsGrams;
  final double totalFatGrams;
  final NutritionDayType dayType;
  final NutritionReportSubmissionType submissionType;
  final int? targetCalories;

  factory DailyNutritionReport.fromEntries({
    required String dateKey,
    required List<DailyNutritionEntry> entries,
    required NutritionDayType dayType,
    NutritionReportSubmissionType submissionType =
        NutritionReportSubmissionType.manual,
    int? targetCalories,
    DateTime? submittedAt,
  }) {
    final totals = DailyNutritionTotals.fromEntries(entries);
    return DailyNutritionReport(
      dateKey: dateKey,
      submittedAt: submittedAt ?? DateTime.now(),
      entries: List.unmodifiable(entries),
      totalCalories: totals.calories,
      totalProteinGrams: totals.proteinGrams,
      totalCarbsGrams: totals.carbsGrams,
      totalFatGrams: totals.fatGrams,
      dayType: dayType,
      submissionType: submissionType,
      targetCalories: targetCalories,
    );
  }

  Map<String, dynamic> toJson() => {
    'dateKey': dateKey,
    'submittedAt': submittedAt.toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'totalCalories': totalCalories,
    'totalProteinGrams': totalProteinGrams,
    'totalCarbsGrams': totalCarbsGrams,
    'totalFatGrams': totalFatGrams,
    'dayType': dayType.name,
    'submissionType': submissionType.name,
    'targetCalories': targetCalories,
  };

  factory DailyNutritionReport.fromJson(Map<String, dynamic> json) {
    final entryJson = _listValue(json['entries']);
    final entries = entryJson
        .whereType<Map>()
        .map(
          (entry) =>
              DailyNutritionEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
    final totals = DailyNutritionTotals.fromEntries(entries);
    return DailyNutritionReport(
      dateKey: _stringValue(json['dateKey']),
      submittedAt:
          DateTime.tryParse(_stringValue(json['submittedAt'])) ??
          DateTime.now(),
      entries: entries,
      totalCalories:
          _numValue(json['totalCalories'])?.toDouble() ?? totals.calories,
      totalProteinGrams:
          _numValue(json['totalProteinGrams'])?.toDouble() ??
          totals.proteinGrams,
      totalCarbsGrams:
          _numValue(json['totalCarbsGrams'])?.toDouble() ?? totals.carbsGrams,
      totalFatGrams:
          _numValue(json['totalFatGrams'])?.toDouble() ?? totals.fatGrams,
      dayType: NutritionDayType.values.firstWhere(
        (value) => value.name == json['dayType'],
        orElse: () => NutritionDayType.rest,
      ),
      submissionType: NutritionReportSubmissionType.values.firstWhere(
        (value) => value.name == json['submissionType'],
        orElse: () => NutritionReportSubmissionType.manual,
      ),
      targetCalories: _numValue(json['targetCalories'])?.toInt(),
    );
  }
}

String _stringValue(Object? value) => value is String ? value : '';

num? _numValue(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

List<dynamic> _listValue(Object? value) =>
    value is List ? List<dynamic>.from(value) : const [];

String nutritionDateKey(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

bool canSubmitNutritionReport(
  Iterable<DailyNutritionReport> reports,
  String dateKey,
) {
  return !reports.any((report) => report.dateKey == dateKey);
}
