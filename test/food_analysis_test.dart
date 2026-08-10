import 'dart:convert';

import 'package:calorie_tracker/features/nutrition/models/food_analysis_result.dart';
import 'package:calorie_tracker/features/nutrition/providers/food_analysis_provider.dart';
import 'package:calorie_tracker/features/nutrition/services/food_analysis_service.dart';
import 'package:calorie_tracker/features/nutrition/services/food_name_translation_service.dart';
import 'package:calorie_tracker/features/nutrition/services/food_search_cache_service.dart';
import 'package:calorie_tracker/features/nutrition/services/hybrid_food_analysis_service.dart';
import 'package:calorie_tracker/features/nutrition/services/local_food_database_service.dart';
import 'package:calorie_tracker/features/nutrition/services/persian_food_parser.dart';
import 'package:calorie_tracker/features/nutrition/services/usda_food_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled database resolves Persian foods locally', () async {
    final database = LocalFoodDatabaseService();
    expect((await database.loadFoods()).length, greaterThanOrEqualTo(80));
    expect((await database.findExact('دلمه برگ'))?.nameFa, 'دلمه برگ مو');
  });

  test('hybrid resolver uses local data before translation and USDA', () async {
    final translator = _Translation('unused');
    final usda = _Usda(const []);
    final result = await _service(translator, usda).analyze('۵۰ گرم نان بربری');
    expect(result.items.single.calories, 135);
    expect(result.items.single.sourceType, FoodSourceType.local);
    expect(translator.calls, 0);
    expect(usda.calls, 0);
  });

  test('unknown Persian food is translated before USDA lookup', () async {
    final translator = _Translation('potato chips');
    final usda = _Usda([_candidate()]);
    final result = await _service(
      translator,
      usda,
    ).analyze('۱۰۰ گرم چیپس سیب زمینی');
    expect(usda.query, 'potato chips');
    expect(result.items.single.searchPhrase, 'potato chips');
  });

  test('translation failure preserves manual fallback', () async {
    final translator = _Translation('', available: false);
    final usda = _Usda(const []);
    final result = await _service(translator, usda).analyze('۱۰۰ گرم ناشناخته');
    expect(result.items, isEmpty);
    expect(result.unresolvedItems.single.allowsManualEntry, isTrue);
    expect(
      result.unresolvedItems.single.status,
      FoodResolutionStatus.translationUnavailable,
    );
    expect(usda.calls, 0);
  });

  test(
    'representative local foods resolve offline with correct portions',
    () async {
      final translator = _Translation('unused');
      final usda = _Usda(const []);
      final service = HybridFoodAnalysisService(
        parser: const PersianFoodParser(),
        localDatabase: LocalFoodDatabaseService(),
        usda: usda,
        cache: MemoryFoodSearchCacheService(),
        translation: translator,
      );

      final result = await service.analyze(
        '۲ عدد تخم مرغ + ۱۰۰ گرم برنج + یک موز',
      );

      expect(result.items, hasLength(3));
      expect(result.items[0].calories, 143);
      expect(result.items[1].calories, 130);
      expect(result.items[2].consumedGrams, 118);
      expect(translator.calls, 0);
      expect(usda.calls, 0);
    },
  );

  test(
    'unsupported milliliter input requires action without fake entry',
    () async {
      final usda = _Usda(const []);
      final result = await _service(
        _Translation('unused'),
        usda,
      ).analyze('۲۵۰ میلی‌لیتر شیر');

      expect(result.items, isEmpty);
      expect(result.unresolvedItems.single.foodName, 'شیر');
      expect(result.canConfirm, isFalse);
      expect(usda.calls, 0);
    },
  );

  test('custom food takes precedence over bundled exact aliases', () async {
    final database = LocalFoodDatabaseService(
      customFoodLoader: () async => [
        const LocalFoodDefinition(
          id: 'custom-rice',
          nameFa: 'برنج',
          aliasesFa: [],
          searchTermsEn: [],
          basisAmount: 100,
          calories: 999,
          proteinGrams: 1,
          carbsGrams: 1,
          fatGrams: 1,
          source: 'user_custom',
          defaultGramConversions: {},
          isCustom: true,
        ),
      ],
    );
    expect((await database.findExact('برنج'))?.id, 'custom-rice');
  });

  test('disabled and invalid-key USDA paths stay user friendly', () async {
    expect(await const UsdaFoodDataService(apiKey: '').search('rice'), isEmpty);
    final service = UsdaFoodDataService(
      apiKey: 'invalid',
      transport: const _StatusTransport(403),
    );

    Object? failure;
    try {
      await service.search('rice');
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<FoodAnalysisException>());
    expect(foodAnalysisErrorMessage(failure!), contains('معتبر نیست'));
    expect(foodAnalysisErrorMessage(failure), isNot(contains('403')));
  });

  test('manual fallback rejects an all-zero nutrition entry', () {
    expect(validManualNutritionValues([0, 0, 0, 0]), isFalse);
    expect(validManualNutritionValues([null, 1, 0, 0]), isFalse);
    expect(validManualNutritionValues([10, 0, 0, 0]), isTrue);
  });

  test('rapid repeated calculate shares the active analysis', () async {
    final usda = _Usda([_candidate()]);
    final notifier = FoodAnalysisNotifier(
      _service(_Translation('potato chips'), usda),
    );
    addTearDown(notifier.dispose);

    await Future.wait([
      notifier.analyze('۱۰۰ گرم چیپس سیب زمینی'),
      notifier.analyze('۱۰۰ گرم چیپس سیب زمینی'),
    ]);

    expect(usda.calls, 1);
    expect(notifier.state.batch?.items, hasLength(1));
  });
}

HybridFoodAnalysisService _service(
  FoodNameTranslationService translation,
  UsdaFoodDataService usda,
) {
  final json = jsonEncode({
    'foods': [
      LocalFoodDefinition(
        id: 'barbari',
        nameFa: 'نان بربری',
        aliasesFa: const ['بربری'],
        searchTermsEn: const ['barbari bread'],
        basisAmount: 100,
        calories: 270,
        proteinGrams: 9,
        carbsGrams: 55,
        fatGrams: 2,
        source: 'local_curated',
        defaultGramConversions: const {'برش': 35},
      ).toJson(),
    ],
  });
  return HybridFoodAnalysisService(
    parser: const PersianFoodParser(),
    localDatabase: LocalFoodDatabaseService(jsonTextLoader: () async => json),
    usda: usda,
    cache: MemoryFoodSearchCacheService(),
    translation: translation,
  );
}

FoodAnalysisCandidate _candidate() => const FoodAnalysisCandidate(
  id: 1,
  description: 'Potato chips',
  dataType: 'Foundation',
  caloriesPer100g: 500,
  proteinPer100g: 5,
  carbsPer100g: 50,
  fatPer100g: 30,
  matchScore: 60,
);

class _Usda extends UsdaFoodDataService {
  _Usda(this.results) : super(apiKey: 'test');
  final List<FoodAnalysisCandidate> results;
  int calls = 0;
  String? query;

  @override
  Future<List<FoodAnalysisCandidate>> search(String query) async {
    calls++;
    this.query = query;
    return results;
  }
}

class _Translation implements FoodNameTranslationService {
  _Translation(this.output, {this.available = true});
  final String output;
  final bool available;
  int calls = 0;

  @override
  Future<FoodTranslationResult> translateFoodName(String input) async {
    calls++;
    return FoodTranslationResult(
      originalText: input,
      translatedText: output,
      source: available
          ? TranslationSource.onDeviceMlKit
          : TranslationSource.unavailable,
      isAvailable: available,
    );
  }

  @override
  Future<OnDeviceTranslationAvailability> availability() async =>
      const OnDeviceTranslationAvailability(
        isSupported: true,
        modelsReady: true,
      );

  @override
  Future<void> ensureModelsDownloaded() async {}

  @override
  Future<void> saveUserOverride(
    String persianFoodName,
    String englishText,
  ) async {}
}

class _StatusTransport implements UsdaHttpTransport {
  const _StatusTransport(this.statusCode);
  final int statusCode;

  @override
  Future<UsdaHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async => UsdaHttpResponse(statusCode: statusCode, body: '{}');
}
