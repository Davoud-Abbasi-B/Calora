import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/daily_nutrition_model.dart';
import '../services/food_analysis_service.dart';
import '../services/food_name_translation_service.dart';
import '../services/food_search_cache_service.dart';
import '../services/hybrid_food_analysis_service.dart';
import '../services/local_food_database_service.dart';
import '../services/nutrition_journal_service.dart';
import '../services/persian_food_parser.dart';
import '../services/usda_food_data_service.dart';

const usdaApiKey = String.fromEnvironment('USDA_API_KEY');

final selectedNutritionDayTypeProvider =
    FutureProvider.family<NutritionDayType?, String>((ref, dateKey) {
      return ref.watch(localStorageServiceProvider).loadDayType(dateKey);
    });

final foodSearchCacheProvider = Provider<FoodSearchCacheService>((ref) {
  final storage = ref.watch(localStorageServiceProvider);
  return CallbackFoodSearchCacheService(
    loader: () async => storage.loadUsdaSearchCache(),
    saver: storage.saveUsdaSearchCache,
    clearer: storage.clearUsdaSearchCache,
  );
});

final foodTranslationCacheProvider = Provider<FoodTranslationCacheService>((
  ref,
) {
  final storage = ref.watch(localStorageServiceProvider);
  return CallbackFoodTranslationCacheService(
    loader: () async => storage.loadFoodTranslationCache(),
    saver: storage.saveFoodTranslationCache,
  );
});

final localFoodDatabaseProvider = Provider<LocalFoodDatabaseService>((ref) {
  final storage = ref.watch(localStorageServiceProvider);
  return LocalFoodDatabaseService(
    customFoodLoader: () async => storage.loadCustomFoods(),
  );
});

final foodNameTranslationProvider = Provider<FoodNameTranslationService>((ref) {
  return CachedFoodNameTranslationService(
    cache: ref.watch(foodTranslationCacheProvider),
    onDeviceTranslator: const MethodChannelFoodNameTranslator(),
  );
});

final foodAnalysisServiceProvider = Provider<FoodAnalysisService>((ref) {
  return ref.watch(hybridFoodAnalysisServiceProvider);
});

final hybridFoodAnalysisServiceProvider = Provider<HybridFoodAnalysisService>((
  ref,
) {
  return HybridFoodAnalysisService(
    parser: const PersianFoodParser(),
    localDatabase: ref.watch(localFoodDatabaseProvider),
    usda: const UsdaFoodDataService(apiKey: usdaApiKey),
    cache: ref.watch(foodSearchCacheProvider),
    translation: ref.watch(foodNameTranslationProvider),
  );
});

final nutritionJournalServiceProvider = Provider<NutritionJournalService>(
  (ref) => NutritionJournalService(ref.watch(localStorageServiceProvider)),
);
