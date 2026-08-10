import 'package:hive_flutter/hive_flutter.dart';

import '../../features/nutrition/models/daily_nutrition_model.dart';
import '../../features/nutrition/services/local_food_database_service.dart';
import '../../features/nutrition/services/persian_food_parser.dart';
import '../../features/settings/models/calorie_targets.dart';
import 'storage_keys.dart';

class LocalStorageService {
  LocalStorageService(this._box);

  static const boxName = 'calorie_tracker';
  static LocalStorageService? _instance;

  static LocalStorageService get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('LocalStorageService.initialize() has not completed.');
    }
    return value;
  }

  static Future<LocalStorageService> initialize() async {
    await Hive.initFlutter();
    final service = LocalStorageService(await Hive.openBox<dynamic>(boxName));
    _instance = service;
    return service;
  }

  final Box<dynamic> _box;

  Future<void> saveCalorieTargets(CalorieTargets targets) =>
      _box.put(StorageKeys.calorieTargets, targets.toJson());

  CalorieTargets? loadCalorieTargets() {
    final value = _stringMap(_box.get(StorageKeys.calorieTargets));
    if (value == null) return null;
    try {
      final targets = CalorieTargets.fromJson(value);
      if (targets.trainingDayCalories <= 0 || targets.restDayCalories <= 0) {
        return null;
      }
      return targets;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> saveDayType(String dateKey, NutritionDayType dayType) async {
    final values = _mapValue(StorageKeys.selectedDayTypes);
    values[dateKey] = dayType.name;
    await _box.put(StorageKeys.selectedDayTypes, values);
  }

  NutritionDayType? loadDayType(String dateKey) {
    final metadata = loadDailyNutritionMetadata(dateKey);
    if (metadata != null) return metadata.dayType;
    final stored = _mapValue(StorageKeys.selectedDayTypes)[dateKey];
    if (stored is! String) return null;
    return NutritionDayType.values
        .where((value) => value.name == stored)
        .firstOrNull;
  }

  Future<void> saveDailyNutritionMetadata(
    DailyNutritionMetadata metadata,
  ) async {
    final values = _mapValue(StorageKeys.dailyNutritionMetadata);
    values[metadata.dateKey] = metadata.toJson();
    await _box.put(StorageKeys.dailyNutritionMetadata, values);
    await saveDayType(metadata.dateKey, metadata.dayType);
  }

  DailyNutritionMetadata? loadDailyNutritionMetadata(String dateKey) {
    final raw = _mapValue(StorageKeys.dailyNutritionMetadata)[dateKey];
    final value = _stringMap(raw);
    return value == null ? null : DailyNutritionMetadata.fromJson(value);
  }

  Future<void> saveDailyNutritionDraft(
    String dateKey,
    List<DailyNutritionEntry> entries,
  ) async {
    final drafts = _mapValue(StorageKeys.dailyNutritionDrafts);
    drafts[dateKey] = entries.map((entry) => entry.toJson()).toList();
    await _box.put(StorageKeys.dailyNutritionDrafts, drafts);
  }

  List<DailyNutritionEntry> loadDailyNutritionDraft(String dateKey) {
    final raw = _mapValue(StorageKeys.dailyNutritionDrafts)[dateKey];
    if (raw is! List) return const [];
    return raw
        .map(_stringMap)
        .whereType<Map<String, dynamic>>()
        .map(DailyNutritionEntry.fromJson)
        .toList(growable: false);
  }

  List<String> loadDailyNutritionDraftDateKeys() =>
      _mapValue(StorageKeys.dailyNutritionDrafts).keys.toList(growable: false);

  List<DailyNutritionReport> loadDailyNutritionReports() {
    final reports = _mapValue(StorageKeys.dailyNutritionReports).values
        .map(_stringMap)
        .whereType<Map<String, dynamic>>()
        .map(DailyNutritionReport.fromJson)
        .toList();
    reports.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return reports;
  }

  DailyNutritionReport? loadDailyNutritionReport(String dateKey) {
    final raw = _mapValue(StorageKeys.dailyNutritionReports)[dateKey];
    final value = _stringMap(raw);
    return value == null ? null : DailyNutritionReport.fromJson(value);
  }

  Future<bool> removeDailyNutritionReport(String dateKey) async {
    final reports = _mapValue(StorageKeys.dailyNutritionReports);
    if (!reports.containsKey(dateKey)) return false;
    reports.remove(dateKey);
    await _box.put(StorageKeys.dailyNutritionReports, reports);
    return true;
  }

  Future<DailyNutritionReport> finalizeDailyNutritionReport({
    required String dateKey,
    required NutritionDayType dayType,
    NutritionReportSubmissionType submissionType =
        NutritionReportSubmissionType.manual,
    int? targetCalories,
    DateTime? submittedAt,
  }) async {
    final existing = loadDailyNutritionReport(dateKey);
    if (existing != null) return existing;
    final report = DailyNutritionReport.fromEntries(
      dateKey: dateKey,
      entries: loadDailyNutritionDraft(dateKey),
      dayType: dayType,
      submissionType: submissionType,
      targetCalories: targetCalories,
      submittedAt: submittedAt,
    );
    final reports = _mapValue(StorageKeys.dailyNutritionReports);
    reports[dateKey] = report.toJson();
    await _box.put(StorageKeys.dailyNutritionReports, reports);
    return report;
  }

  Map<String, dynamic> loadUsdaSearchCache() =>
      _mapValue(StorageKeys.usdaFoodSearchCache);

  Future<void> saveUsdaSearchCache(Map<String, dynamic> value) =>
      _box.put(StorageKeys.usdaFoodSearchCache, value);

  Future<void> clearUsdaSearchCache() =>
      _box.delete(StorageKeys.usdaFoodSearchCache);

  Map<String, dynamic> loadFoodTranslationCache() =>
      _mapValue(StorageKeys.foodTranslationCache);

  Future<void> saveFoodTranslationCache(Map<String, dynamic> value) =>
      _box.put(StorageKeys.foodTranslationCache, value);

  List<LocalFoodDefinition> loadCustomFoods() {
    final raw = _box.get(StorageKeys.customFoods);
    if (raw is! List) return const [];
    return raw
        .map(_stringMap)
        .whereType<Map<String, dynamic>>()
        .map(LocalFoodDefinition.fromJson)
        .where((food) => food.id.isNotEmpty && food.nameFa.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveCustomFoods(List<LocalFoodDefinition> foods) => _box.put(
    StorageKeys.customFoods,
    foods.map((food) => food.toJson()).toList(),
  );

  Future<void> saveCustomFood(LocalFoodDefinition food) async {
    final foods = loadCustomFoods();
    final withoutDuplicate = foods
        .where(
          (item) =>
              normalizeFoodName(item.nameFa) != normalizeFoodName(food.nameFa),
        )
        .toList();
    await saveCustomFoods([food, ...withoutDuplicate]);
  }

  Map<String, dynamic> _mapValue(String key) =>
      _stringMap(_box.get(key)) ?? <String, dynamic>{};
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry(key.toString(), _plainValue(item)));
}

Object? _plainValue(Object? value) {
  if (value is Map) return _stringMap(value);
  if (value is List) return value.map(_plainValue).toList();
  return value;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
