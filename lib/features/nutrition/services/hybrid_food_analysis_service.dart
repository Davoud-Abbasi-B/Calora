import '../models/food_analysis_result.dart';
import 'food_analysis_service.dart';
import 'food_name_translation_service.dart';
import 'food_search_cache_service.dart';
import 'local_food_database_service.dart';
import 'persian_food_parser.dart';
import 'usda_food_data_service.dart';

class HybridFoodAnalysisService implements FoodAnalysisService {
  const HybridFoodAnalysisService({
    required this.parser,
    required this.localDatabase,
    required this.usda,
    required this.cache,
    required this.translation,
  });

  final PersianFoodParser parser;
  final LocalFoodDatabaseService localDatabase;
  final UsdaFoodDataService usda;
  final FoodSearchCacheService cache;
  final FoodNameTranslationService translation;

  bool get isOnlineSearchConfigured => usda.isConfigured;

  @override
  Future<FoodAnalysisBatchResult> analyze(String input) async {
    final parsedItems = parser.parse(input);
    if (parsedItems.isEmpty) {
      throw const FoodAnalysisException(FoodAnalysisErrorType.badRequest);
    }

    final results = <FoodAnalysisResult>[];
    final unresolved = <UnresolvedFoodItem>[];
    final warnings = <String>[];
    for (final parsed in parsedItems) {
      if (parsed.isQuantityAmbiguous) {
        unresolved.add(
          _unresolved(
            parsed,
            'مقدار مصرف مشخص نشده است.',
            status: FoodResolutionStatus.needsPortion,
          ),
        );
        continue;
      }
      if (parsed.hasUnsupportedUnit) {
        unresolved.add(
          _unresolved(
            parsed,
            'واحد واردشده پشتیبانی نمی‌شود.',
            status: FoodResolutionStatus.needsPortion,
          ),
        );
        continue;
      }

      final local = await localDatabase.findExact(parsed.normalizedFoodName);
      if (local != null) {
        final grams = consumedGrams(parsed, local: local);
        if (grams == null) {
          unresolved.add(
            _unresolved(
              parsed,
              parsed.unit == FoodUnit.item
                  ? 'وزن تقریبی هر عدد مشخص نیست.'
                  : 'برای این واحد تبدیل مطمئنی وجود ندارد؛ مقدار را به گرم وارد کنید.',
              status: FoodResolutionStatus.needsPortion,
            ),
          );
          continue;
        }
        results.add(resultFromLocal(parsed, local, grams));
        continue;
      }

      if (!usda.isConfigured) {
        unresolved.add(
          _unresolved(
            parsed,
            'این خوراکی در پایگاه داده موجود نیست.',
            status: FoodResolutionStatus.notFound,
          ),
        );
        continue;
      }

      final translated = await translation.translateFoodName(
        parsed.normalizedFoodName,
      );
      if (!translated.isAvailable) {
        unresolved.add(
          _unresolved(
            parsed,
            translated.warning ?? 'مترجم آفلاین در دسترس نیست.',
            status: FoodResolutionStatus.translationUnavailable,
          ),
        );
        continue;
      }
      final phrase = translated.normalizedSearchText;

      try {
        final cached = await cache.get(phrase);
        if (cached?.selectedCandidate != null) {
          final selected = cached!.selectedCandidate!;
          final grams = consumedGrams(parsed, candidate: selected);
          if (grams == null) {
            unresolved.add(
              _unresolved(
                parsed,
                'برای این واحد، وزن قابل اتکایی پیدا نشد.',
                status: FoodResolutionStatus.needsPortion,
                searchPhrase: phrase,
                candidates: [selected],
              ),
            );
          } else {
            results.add(resultFromUsda(parsed, selected, grams, phrase));
          }
          continue;
        }

        final candidates =
            cached?.candidates ?? await _searchUsdaVariants(phrase);
        if (cached == null) {
          await cache.put(
            FoodSearchCacheEntry(
              query: phrase,
              candidates: candidates,
              timestamp: DateTime.now(),
            ),
          );
        }
        final clear = clearCandidate(candidates);
        if (clear != null) {
          final grams = consumedGrams(parsed, candidate: clear);
          if (grams != null) {
            results.add(resultFromUsda(parsed, clear, grams, phrase));
            continue;
          }
        }
        unresolved.add(
          _unresolved(
            parsed,
            'چند خوراکی مشابه پیدا شد؛ یکی را انتخاب کنید.',
            status: FoodResolutionStatus.ambiguous,
            searchPhrase: phrase,
            candidates: candidates.take(5).toList(growable: false),
          ),
        );
      } on FoodAnalysisException catch (error) {
        if (error.type == FoodAnalysisErrorType.noResults) {
          unresolved.add(
            _unresolved(
              parsed,
              foodAnalysisErrorMessage(error),
              status: FoodResolutionStatus.notFound,
              searchPhrase: phrase,
            ),
          );
        } else {
          warnings.add(foodAnalysisErrorMessage(error));
          unresolved.add(
            _unresolved(
              parsed,
              foodAnalysisErrorMessage(error),
              status: FoodResolutionStatus.notFound,
              searchPhrase: phrase,
            ),
          );
        }
      }
    }

    return FoodAnalysisBatchResult(
      originalInput: input,
      items: results,
      unresolvedItems: unresolved,
      warnings: warnings,
    );
  }

  FoodAnalysisCandidate? clearCandidate(
    List<FoodAnalysisCandidate> candidates,
  ) {
    if (candidates.isEmpty) return null;
    final first = candidates.first;
    final secondScore = candidates.length > 1 ? candidates[1].matchScore : -999;
    if (first.matchScore >= 35 && first.matchScore - secondScore >= 12) {
      return first;
    }
    return null;
  }

  Future<FoodAnalysisResult?> resolveCandidate(
    UnresolvedFoodItem unresolved,
    FoodAnalysisCandidate candidate,
  ) async {
    final parsed = ParsedFoodInput(
      originalSegment: unresolved.originalSegment,
      normalizedFoodName: unresolved.foodName,
      quantity: unresolved.quantity,
      unit: FoodUnit.values.firstWhere(
        (unit) => unit.name == unresolved.unit,
        orElse: () => FoodUnit.unsupported,
      ),
      quantityText: unresolved.quantityText,
    );
    final grams = consumedGrams(parsed, candidate: candidate);
    if (grams == null) return null;
    if (unresolved.searchPhrase != null) {
      await cache.select(unresolved.searchPhrase!, candidate);
    }
    return resultFromUsda(parsed, candidate, grams, unresolved.searchPhrase);
  }

  Future<FoodAnalysisBatchResult> analyzeWithUserTranslation(
    UnresolvedFoodItem unresolved,
    String englishPhrase, {
    required bool saveForLater,
  }) async {
    final phrase = normalizeEnglishFoodQuery(englishPhrase);
    if (phrase.isEmpty || !usda.isConfigured) {
      return FoodAnalysisBatchResult(
        originalInput: unresolved.originalSegment,
        items: const [],
        unresolvedItems: [unresolved],
      );
    }
    if (saveForLater) {
      await translation.saveUserOverride(unresolved.foodName, phrase);
    }
    final parsed = _parsedFromUnresolved(unresolved);
    try {
      final candidates = await _searchUsdaVariants(phrase);
      await cache.put(
        FoodSearchCacheEntry(
          query: phrase,
          candidates: candidates,
          timestamp: DateTime.now(),
        ),
      );
      final clear = clearCandidate(candidates);
      if (clear != null) {
        final grams = consumedGrams(parsed, candidate: clear);
        if (grams != null) {
          return FoodAnalysisBatchResult(
            originalInput: unresolved.originalSegment,
            items: [resultFromUsda(parsed, clear, grams, phrase)],
          );
        }
      }
      return FoodAnalysisBatchResult(
        originalInput: unresolved.originalSegment,
        items: const [],
        unresolvedItems: [
          _unresolved(
            parsed,
            'چند خوراکی مشابه پیدا شد؛ یکی را انتخاب کنید.',
            status: FoodResolutionStatus.ambiguous,
            searchPhrase: phrase,
            candidates: candidates.take(5).toList(growable: false),
          ),
        ],
      );
    } on FoodAnalysisException catch (error) {
      return FoodAnalysisBatchResult(
        originalInput: unresolved.originalSegment,
        items: const [],
        unresolvedItems: [
          _unresolved(
            parsed,
            foodAnalysisErrorMessage(error),
            status: FoodResolutionStatus.notFound,
            searchPhrase: phrase,
          ),
        ],
      );
    }
  }

  Future<FoodAnalysisResult?> resolveLocalPortion(
    UnresolvedFoodItem unresolved,
    double gramsPerItem,
  ) async {
    if (unresolved.status != FoodResolutionStatus.needsPortion ||
        unresolved.unit != FoodUnit.item.name ||
        unresolved.quantity == null ||
        gramsPerItem <= 0) {
      return null;
    }
    final local = await localDatabase.findExact(unresolved.foodName);
    if (local == null) return null;
    final parsed = ParsedFoodInput(
      originalSegment: unresolved.originalSegment,
      normalizedFoodName: unresolved.foodName,
      quantity: unresolved.quantity,
      unit: FoodUnit.item,
      quantityText: unresolved.quantityText,
    );
    return resultFromLocal(
      parsed,
      local,
      unresolved.quantity! * gramsPerItem,
      gramsPerItem: gramsPerItem,
    );
  }

  Future<List<FoodAnalysisCandidate>> _searchUsdaVariants(
    String primaryPhrase,
  ) async {
    List<FoodAnalysisCandidate>? firstPlausible;
    FoodAnalysisException? lastNoResult;
    for (final query in _usdaQueryVariants(primaryPhrase)) {
      try {
        final candidates = await usda.search(query);
        firstPlausible ??= candidates;
        if (clearCandidate(candidates) != null) return candidates;
      } on FoodAnalysisException catch (error) {
        if (error.type != FoodAnalysisErrorType.noResults) rethrow;
        lastNoResult = error;
      }
    }
    if (firstPlausible != null) return firstPlausible;
    throw lastNoResult ??
        const FoodAnalysisException(FoodAnalysisErrorType.noResults);
  }

  static double? consumedGrams(
    ParsedFoodInput parsed, {
    LocalFoodDefinition? local,
    FoodAnalysisCandidate? candidate,
  }) {
    final quantity = parsed.quantity;
    final unit = parsed.unit;
    if (quantity == null || unit == null) return null;
    if (unit == FoodUnit.gram) return quantity;
    if (unit == FoodUnit.kilogram) return quantity * 1000;
    final conversion = local?.defaultGramConversions[unit.label];
    if (conversion != null) return quantity * conversion;
    final servingSize = candidate?.servingSize;
    final servingUnit = candidate?.servingSizeUnit?.toLowerCase();
    if (servingSize != null &&
        servingSize > 0 &&
        (servingUnit == 'g' || servingUnit == 'gram')) {
      return quantity * servingSize;
    }
    return null;
  }

  static FoodAnalysisResult resultFromLocal(
    ParsedFoodInput parsed,
    LocalFoodDefinition food,
    double grams, {
    double? gramsPerItem,
  }) {
    final multiplier = grams / food.basisAmount;
    final configuredItemGrams = parsed.unit == FoodUnit.item
        ? gramsPerItem ?? food.defaultGramConversions[FoodUnit.item.label]
        : null;
    return FoodAnalysisResult(
      originalInput: parsed.originalSegment,
      foodName: food.nameFa,
      quantityText: parsed.quantityText,
      consumedGrams: grams,
      calories: _round(food.calories * multiplier),
      proteinGrams: _round(food.proteinGrams * multiplier),
      carbsGrams: _round(food.carbsGrams * multiplier),
      fatGrams: _round(food.fatGrams * multiplier),
      isEstimated: food.isEstimated,
      confidence: food.isCustom ? 'high' : 'medium',
      assumptions: [
        ...food.assumptions,
        if (configuredItemGrams != null)
          'وزن تقریبی هر عدد: ${_formatGramValue(configuredItemGrams)} گرم',
      ],
      warnings: [
        ...food.warnings,
        if (food.warnings.isEmpty) 'مقادیر تقریبی هستند.',
      ],
      sourceType: food.isCustom ? FoodSourceType.manual : FoodSourceType.local,
      sourceLabel: food.isCustom ? 'خوراکی‌های من' : 'پایگاه داخلی',
    );
  }

  static FoodAnalysisResult resultFromUsda(
    ParsedFoodInput parsed,
    FoodAnalysisCandidate candidate,
    double grams,
    String? searchPhrase,
  ) {
    final multiplier = grams / 100;
    return FoodAnalysisResult(
      originalInput: parsed.originalSegment,
      foodName: parsed.normalizedFoodName,
      quantityText: parsed.quantityText,
      consumedGrams: grams,
      calories: _round(candidate.caloriesPer100g * multiplier),
      proteinGrams: _round(candidate.proteinPer100g * multiplier),
      carbsGrams: _round(candidate.carbsPer100g * multiplier),
      fatGrams: _round(candidate.fatPer100g * multiplier),
      isEstimated: true,
      confidence: candidate.matchScore >= 50 ? 'high' : 'medium',
      assumptions: ['تطبیق با ${candidate.description}'],
      warnings: const ['مقادیر بر اساس داده USDA و وزن مصرفی محاسبه شده‌اند.'],
      sourceType: FoodSourceType.usda,
      sourceLabel: 'USDA FoodData Central',
      fdcId: candidate.id,
      searchPhrase: searchPhrase,
    );
  }

  static UnresolvedFoodItem _unresolved(
    ParsedFoodInput parsed,
    String reason, {
    required FoodResolutionStatus status,
    String? searchPhrase,
    List<FoodAnalysisCandidate> candidates = const [],
  }) => UnresolvedFoodItem(
    originalSegment: parsed.originalSegment,
    foodName: parsed.normalizedFoodName,
    quantityText: parsed.quantityText,
    quantity: parsed.quantity,
    unit: parsed.unit?.name,
    reason: reason,
    status: status,
    searchPhrase: searchPhrase,
    candidates: candidates,
  );

  static ParsedFoodInput _parsedFromUnresolved(UnresolvedFoodItem unresolved) =>
      ParsedFoodInput(
        originalSegment: unresolved.originalSegment,
        normalizedFoodName: unresolved.foodName,
        quantity: unresolved.quantity,
        unit: FoodUnit.values.firstWhere(
          (unit) => unit.name == unresolved.unit,
          orElse: () => FoodUnit.unsupported,
        ),
        quantityText: unresolved.quantityText,
      );
}

double _round(double value) => double.parse(value.toStringAsFixed(1));

String _formatGramValue(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

List<String> _usdaQueryVariants(String primaryPhrase) {
  final normalized = normalizeEnglishFoodQuery(primaryPhrase);
  final variants = <String>[normalized];
  final tokens = normalized.split(' ');
  for (final modifier in const ['cooked', 'raw']) {
    final index = tokens.indexOf(modifier);
    if (index > 0) {
      final reordered = [
        modifier,
        ...tokens.where((token) => token != modifier),
      ].join(' ');
      if (!variants.contains(reordered)) variants.add(reordered);
      break;
    }
  }
  return variants.take(2).toList(growable: false);
}
