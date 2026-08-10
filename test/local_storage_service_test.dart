import 'dart:io';

import 'package:calorie_tracker/data/local/local_storage_service.dart';
import 'package:calorie_tracker/data/local/storage_keys.dart';
import 'package:calorie_tracker/features/nutrition/models/food_analysis_result.dart';
import 'package:calorie_tracker/features/nutrition/models/daily_nutrition_model.dart';
import 'package:calorie_tracker/features/nutrition/services/food_name_translation_service.dart';
import 'package:calorie_tracker/features/nutrition/services/food_search_cache_service.dart';
import 'package:calorie_tracker/features/nutrition/services/local_food_database_service.dart';
import 'package:calorie_tracker/features/nutrition/services/nutrition_journal_service.dart';
import 'package:calorie_tracker/features/settings/models/calorie_targets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late LocalStorageService storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('calorie_tracker_test_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      'test_${DateTime.now().microsecondsSinceEpoch}',
    );
    storage = LocalStorageService(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await directory.delete(recursive: true);
  });

  test('saves and loads user-defined calorie targets', () async {
    const targets = CalorieTargets(
      trainingDayCalories: 2400,
      restDayCalories: 2000,
    );
    expect(storage.loadCalorieTargets(), isNull);
    await storage.saveCalorieTargets(targets);
    final loaded = storage.loadCalorieTargets();
    expect(loaded?.trainingDayCalories, 2400);
    expect(loaded?.restDayCalories, 2000);
  });

  test('persists a daily draft', () async {
    await storage.saveDailyNutritionDraft('2026-08-10', [_entry()]);
    final loaded = storage.loadDailyNutritionDraft('2026-08-10');
    expect(loaded.single.foodName, 'تخم‌مرغ');
    expect(loaded.single.calories, 70);
  });

  test('finalization persists once and retains the underlying draft', () async {
    await storage.saveDailyNutritionDraft('2026-08-10', [_entry()]);
    final automatic = await storage.finalizeDailyNutritionReport(
      dateKey: '2026-08-10',
      dayType: NutritionDayType.training,
      submissionType: NutritionReportSubmissionType.automatic,
      submittedAt: DateTime(2026, 8, 10, 23, 59),
    );
    final duplicate = await storage.finalizeDailyNutritionReport(
      dateKey: '2026-08-10',
      dayType: NutritionDayType.rest,
      submissionType: NutritionReportSubmissionType.manual,
    );

    expect(storage.loadDailyNutritionReports(), hasLength(1));
    expect(duplicate.submittedAt, automatic.submittedAt);
    expect(duplicate.dayType, NutritionDayType.training);
    expect(duplicate.submissionType, NutritionReportSubmissionType.automatic);
    expect(storage.loadDailyNutritionDraft('2026-08-10'), hasLength(1));
  });

  test('submission type serializes and legacy reports default to manual', () {
    final report = DailyNutritionReport.fromEntries(
      dateKey: '2026-08-10',
      entries: [_entry()],
      dayType: NutritionDayType.rest,
      submissionType: NutritionReportSubmissionType.automatic,
      targetCalories: 2000,
    );
    expect(
      DailyNutritionReport.fromJson(report.toJson()).submissionType,
      NutritionReportSubmissionType.automatic,
    );
    expect(DailyNutritionReport.fromJson(report.toJson()).targetCalories, 2000);
    final legacy = Map<String, dynamic>.from(report.toJson())
      ..remove('submissionType');
    expect(
      DailyNutritionReport.fromJson(legacy).submissionType,
      NutritionReportSubmissionType.manual,
    );
    legacy.remove('targetCalories');
    expect(DailyNutritionReport.fromJson(legacy).targetCalories, isNull);
  });

  test('malformed optional legacy values fall back without crashing', () async {
    final report =
        DailyNutritionReport.fromEntries(
            dateKey: '2026-08-10',
            entries: [_entry()],
            dayType: NutritionDayType.training,
          ).toJson()
          ..['targetCalories'] = <String, Object?>{}
          ..['submissionType'] = 42
          ..['totalCalories'] = '70';
    await box.put(StorageKeys.dailyNutritionReports, {'2026-08-10': report});

    final loaded = storage.loadDailyNutritionReport('2026-08-10');
    expect(loaded?.targetCalories, isNull);
    expect(loaded?.submissionType, NutritionReportSubmissionType.manual);
    expect(loaded?.totalCalories, 70);

    expect(
      FoodTranslationCacheEntry.fromJson({
        'persianText': 12,
        'englishText': null,
        'createdAt': <String, Object?>{},
      }).createdAt,
      DateTime(1970),
    );
    expect(
      FoodSearchCacheEntry.fromJson({
        'query': 12,
        'candidates': 'invalid',
        'timestamp': false,
      }).candidates,
      isEmpty,
    );
    expect(
      FoodAnalysisCandidate.fromJson({'id': '123', 'servingSize': '50'}).id,
      123,
    );
    expect(
      LocalFoodDefinition.fromJson({
        'id': 'legacy',
        'nameFa': 'خوراک قدیمی',
        'defaultGramConversions': {'عدد': 'invalid'},
      }).defaultGramConversions,
      isEmpty,
    );
  });

  test('malformed stored targets route back to onboarding safely', () async {
    await box.put(StorageKeys.calorieTargets, {
      'trainingDayCalories': 'invalid',
      'restDayCalories': 1900,
    });
    expect(storage.loadCalorieTargets(), isNull);
  });

  test('custom foods replace normalized duplicate names', () async {
    LocalFoodDefinition food(String id, String name) => LocalFoodDefinition(
      id: id,
      nameFa: name,
      aliasesFa: const [],
      searchTermsEn: const [],
      basisAmount: 100,
      calories: 100,
      proteinGrams: 1,
      carbsGrams: 1,
      fatGrams: 1,
      source: 'user_custom',
      defaultGramConversions: const {},
      isCustom: true,
    );

    await storage.saveCustomFood(food('first', 'نان‌جو'));
    await storage.saveCustomFood(food('second', 'نان جو'));

    expect(storage.loadCustomFoods(), hasLength(1));
    expect(storage.loadCustomFoods().single.id, 'second');
  });

  test(
    'day type is stored by user choice and not inferred from weekday',
    () async {
      await storage.saveDayType('2026-08-10', NutritionDayType.rest);
      await storage.saveDayType('2026-08-11', NutritionDayType.training);
      expect(storage.loadDayType('2026-08-10'), NutritionDayType.rest);
      expect(storage.loadDayType('2026-08-11'), NutritionDayType.training);
      expect(storage.loadDayType('2026-08-12'), isNull);
    },
  );

  test('analysis results become separate draft entries', () {
    final entries = dailyNutritionEntriesFromAnalyses(
      [
        const FoodAnalysisResult(
          originalInput: 'یک موز',
          foodName: 'موز',
          quantityText: 'یک عدد',
          calories: 100,
          proteinGrams: 1,
          carbsGrams: 20,
          fatGrams: 0,
          isEstimated: true,
        ),
        const FoodAnalysisResult(
          originalInput: 'یک موز',
          foodName: 'موز',
          quantityText: 'یک عدد',
          calories: 100,
          proteinGrams: 1,
          carbsGrams: 20,
          fatGrams: 0,
          isEstimated: true,
        ),
      ],
      dateKey: '2026-08-10',
      createdAt: DateTime(2026, 8, 10),
    );
    expect(entries, hasLength(2));
    expect(entries[0].id, isNot(entries[1].id));
  });
}

DailyNutritionEntry _entry() => DailyNutritionEntry(
  id: 'egg-1',
  dateKey: '2026-08-10',
  createdAt: DateTime(2026, 8, 10, 8),
  originalInput: '۱ عدد تخم‌مرغ',
  foodName: 'تخم‌مرغ',
  quantityText: '۱ عدد',
  calories: 70,
  proteinGrams: 6,
  carbsGrams: 0.5,
  fatGrams: 5,
  isEstimated: true,
);
