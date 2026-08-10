import 'dart:convert';

import 'package:flutter/services.dart';

import 'persian_food_parser.dart';

class LocalFoodDefinition {
  const LocalFoodDefinition({
    required this.id,
    required this.nameFa,
    required this.aliasesFa,
    required this.searchTermsEn,
    required this.basisAmount,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    required this.source,
    required this.defaultGramConversions,
    this.assumptions = const [],
    this.warnings = const [],
    this.isEstimated = true,
    this.isCustom = false,
  });

  final String id;
  final String nameFa;
  final List<String> aliasesFa;
  final List<String> searchTermsEn;
  final double basisAmount;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final String source;
  final Map<String, double> defaultGramConversions;
  final List<String> assumptions;
  final List<String> warnings;
  final bool isEstimated;
  final bool isCustom;

  factory LocalFoodDefinition.fromJson(Map<String, dynamic> json) {
    final conversions = json['defaultGramConversions'] is Map
        ? json['defaultGramConversions'] as Map
        : const {};
    return LocalFoodDefinition(
      id: json['id'] is String ? json['id'] as String : '',
      nameFa: json['nameFa'] is String ? json['nameFa'] as String : '',
      aliasesFa:
          (json['aliasesFa'] is List
                  ? json['aliasesFa'] as List
                  : const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      searchTermsEn:
          (json['searchTermsEn'] is List
                  ? json['searchTermsEn'] as List
                  : const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      basisAmount: _numValue(json['basisAmount'])?.toDouble() ?? 100,
      calories: _numValue(json['calories'])?.toDouble() ?? 0,
      proteinGrams: _numValue(json['proteinGrams'])?.toDouble() ?? 0,
      carbsGrams: _numValue(json['carbsGrams'])?.toDouble() ?? 0,
      fatGrams: _numValue(json['fatGrams'])?.toDouble() ?? 0,
      source: json['source'] is String
          ? json['source'] as String
          : 'local_curated',
      defaultGramConversions: {
        for (final entry in conversions.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      },
      assumptions:
          (json['assumptions'] is List
                  ? json['assumptions'] as List
                  : const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      warnings:
          (json['warnings'] is List
                  ? json['warnings'] as List
                  : const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      isEstimated: json['isEstimated'] is bool
          ? json['isEstimated'] as bool
          : true,
      isCustom: json['isCustom'] is bool ? json['isCustom'] as bool : false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nameFa': nameFa,
    'aliasesFa': aliasesFa,
    'searchTermsEn': searchTermsEn,
    'basisUnit': 'gram',
    'basisAmount': basisAmount,
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'fatGrams': fatGrams,
    'source': source,
    'defaultGramConversions': defaultGramConversions,
    'assumptions': assumptions,
    'warnings': warnings,
    'isEstimated': isEstimated,
    'isCustom': isCustom,
  };
}

class LocalFoodDatabaseService {
  LocalFoodDatabaseService({
    AssetBundle? assetBundle,
    this.customFoodLoader,
    this.jsonTextLoader,
    this.assetPath = 'assets/data/persian_food_database.json',
  }) : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  final Future<List<LocalFoodDefinition>> Function()? customFoodLoader;
  final Future<String> Function()? jsonTextLoader;
  final String assetPath;
  List<LocalFoodDefinition>? _foods;

  Future<List<LocalFoodDefinition>> loadFoods() async {
    if (_foods != null) return _foods!;
    final text =
        await jsonTextLoader?.call() ??
        await _assetBundle.loadString(assetPath);
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final bundled = (decoded['foods'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              LocalFoodDefinition.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    final custom = await customFoodLoader?.call() ?? const [];
    _foods = [...custom, ...bundled];
    return _foods!;
  }

  Future<LocalFoodDefinition?> findExact(String foodName) async {
    final target = normalizeFoodName(foodName);
    final foods = await loadFoods();
    for (final food in foods.where((food) => food.isCustom)) {
      if (_matches(food, target)) return food;
    }
    for (final food in foods.where((food) => !food.isCustom)) {
      if (_matches(food, target)) return food;
    }
    return null;
  }

  bool _matches(LocalFoodDefinition food, String target) {
    return normalizeFoodName(food.nameFa) == target ||
        food.aliasesFa.any((alias) => normalizeFoodName(alias) == target);
  }

  void invalidateCustomFoods() => _foods = null;
}

class PersianFoodSearchDictionary {
  const PersianFoodSearchDictionary();

  String? searchPhrase(
    String normalizedFoodName, {
    LocalFoodDefinition? localDefinition,
  }) {
    if (localDefinition != null && localDefinition.searchTermsEn.isNotEmpty) {
      return localDefinition.searchTermsEn.first;
    }
    return _terms[normalizeFoodName(normalizedFoodName)];
  }

  static const _terms = <String, String>{
    'پنیر لیقوان': 'white brined sheep milk cheese',
    'پنیر فتا': 'feta cheese',
    'پنیر سفید': 'white brined cheese',
    'نان بربری': 'Iranian flatbread',
    'نان سنگک': 'Iranian whole wheat flatbread',
    'نان لواش': 'lavash flatbread',
    'سینه مرغ': 'chicken breast cooked skinless',
    'سینه مرغ پخته': 'chicken breast meat only cooked',
    'سینه مرغ خام': 'chicken breast meat only raw',
    'ران مرغ': 'chicken thigh cooked meat only',
    'برنج پخته': 'rice white cooked',
    'برنج ایرانی': 'rice white cooked',
    'ماست یونانی': 'Greek yogurt plain',
    'تخم مرغ': 'egg whole cooked',
    'تخم‌مرغ': 'egg whole cooked',
    'شیر کم چرب': 'milk lowfat',
    'شیر پرچرب': 'milk whole',
    'ماهی': 'fish cooked',
    'گوشت گوساله': 'beef cooked lean',
    'جو دوسر': 'oats dry',
    'سیب زمینی': 'potato cooked',
    'موز': 'banana raw',
    'سیب': 'apple raw with skin',
    'آووکادو': 'avocado raw',
    'ماهی سالمون': 'salmon cooked',
    'سالمون': 'salmon cooked',
    'توفو': 'tofu firm prepared with calcium',
    'پنیر چدار': 'cheddar cheese',
    'نان چاودار': 'rye bread',
    'کره بادام': 'almond butter',
    'شیر سویا': 'soy milk unsweetened',
    'شیر بادام': 'almond milk unsweetened',
  };
}

num? _numValue(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}
