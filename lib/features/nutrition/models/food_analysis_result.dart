import 'daily_nutrition_model.dart';

enum FoodSourceType { local, usda, manual }

enum FoodResolutionStatus {
  resolved,
  ambiguous,
  needsPortion,
  notFound,
  translationUnavailable,
}

class FoodAnalysisResult {
  const FoodAnalysisResult({
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
    this.sourceLabel = 'پایگاه داخلی',
    this.fdcId,
    this.searchPhrase,
  });

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
  final String? searchPhrase;

  Map<String, dynamic> toJson() => {
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
    'searchPhrase': searchPhrase,
  };

  factory FoodAnalysisResult.fromJson(Map<String, dynamic> json) {
    return FoodAnalysisResult(
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
      searchPhrase: json['searchPhrase'] is String
          ? json['searchPhrase'] as String
          : null,
    );
  }
}

class FoodAnalysisBatchResult {
  FoodAnalysisBatchResult({
    required this.originalInput,
    required List<FoodAnalysisResult> items,
    List<String> warnings = const [],
    List<UnresolvedFoodItem> unresolvedItems = const [],
  }) : items = List.unmodifiable(items),
       warnings = List.unmodifiable(warnings),
       unresolvedItems = List.unmodifiable(unresolvedItems);

  final String originalInput;
  final List<FoodAnalysisResult> items;
  final List<String> warnings;
  final List<UnresolvedFoodItem> unresolvedItems;

  bool get needsUserAction => unresolvedItems.isNotEmpty;
  bool get hasResolvedItems => items.isNotEmpty;
  bool get canConfirm => hasResolvedItems && !needsUserAction;

  DailyNutritionTotals get totals {
    var calories = 0.0;
    var protein = 0.0;
    var carbs = 0.0;
    var fat = 0.0;
    for (final item in items) {
      calories += item.calories;
      protein += item.proteinGrams;
      carbs += item.carbsGrams;
      fat += item.fatGrams;
    }
    return DailyNutritionTotals(
      calories: calories.roundToDouble(),
      proteinGrams: _oneDecimal(protein),
      carbsGrams: _oneDecimal(carbs),
      fatGrams: _oneDecimal(fat),
    );
  }
}

class FoodAnalysisCandidate {
  const FoodAnalysisCandidate({
    required this.id,
    required this.description,
    required this.dataType,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.matchScore,
    this.brandOwner,
    this.servingSize,
    this.servingSizeUnit,
  });

  final int id;
  final String description;
  final String dataType;
  final String? brandOwner;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double matchScore;
  final double? servingSize;
  final String? servingSizeUnit;

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'dataType': dataType,
    'brandOwner': brandOwner,
    'caloriesPer100g': caloriesPer100g,
    'proteinPer100g': proteinPer100g,
    'carbsPer100g': carbsPer100g,
    'fatPer100g': fatPer100g,
    'matchScore': matchScore,
    'servingSize': servingSize,
    'servingSizeUnit': servingSizeUnit,
  };

  factory FoodAnalysisCandidate.fromJson(Map<String, dynamic> json) =>
      FoodAnalysisCandidate(
        id:
            _numValue(json['id'])?.toInt() ??
            _numValue(json['fdcId'])?.toInt() ??
            0,
        description: _stringValue(json['description']),
        dataType: _stringValue(json['dataType']),
        brandOwner: json['brandOwner'] is String
            ? json['brandOwner'] as String
            : null,
        caloriesPer100g: _numValue(json['caloriesPer100g'])?.toDouble() ?? 0,
        proteinPer100g: _numValue(json['proteinPer100g'])?.toDouble() ?? 0,
        carbsPer100g: _numValue(json['carbsPer100g'])?.toDouble() ?? 0,
        fatPer100g: _numValue(json['fatPer100g'])?.toDouble() ?? 0,
        matchScore: _numValue(json['matchScore'])?.toDouble() ?? 0,
        servingSize: _numValue(json['servingSize'])?.toDouble(),
        servingSizeUnit: json['servingSizeUnit'] is String
            ? json['servingSizeUnit'] as String
            : null,
      );
}

class UnresolvedFoodItem {
  const UnresolvedFoodItem({
    required this.originalSegment,
    required this.foodName,
    required this.quantityText,
    required this.quantity,
    required this.unit,
    required this.reason,
    required this.status,
    this.consumedGrams,
    this.searchPhrase,
    this.candidates = const [],
  });

  final String originalSegment;
  final String foodName;
  final String quantityText;
  final double? quantity;
  final String? unit;
  final double? consumedGrams;
  final String? searchPhrase;
  final String reason;
  final FoodResolutionStatus status;
  final List<FoodAnalysisCandidate> candidates;

  bool get allowsManualEntry => status != FoodResolutionStatus.resolved;
}

double _oneDecimal(double value) => double.parse(value.toStringAsFixed(1));

String _stringValue(Object? value) => value is String ? value : '';

num? _numValue(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

List<dynamic> _listValue(Object? value) =>
    value is List ? List<dynamic>.from(value) : const [];
