import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/food_analysis_result.dart';
import 'food_analysis_service.dart';

const usdaBaseUrl = 'https://api.nal.usda.gov/fdc/v1';

class UsdaHttpResponse {
  const UsdaHttpResponse({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

abstract interface class UsdaHttpTransport {
  Future<UsdaHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  });
}

class IoUsdaHttpTransport implements UsdaHttpTransport {
  const IoUsdaHttpTransport();

  @override
  Future<UsdaHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = method == 'POST'
          ? await client.postUrl(uri).timeout(timeout)
          : await client.getUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      if (body != null) request.write(body);
      final response = await request.close().timeout(timeout);
      return UsdaHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decoder.bind(response).join().timeout(timeout),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class UsdaFoodDataService {
  const UsdaFoodDataService({
    required this.apiKey,
    this.transport = const IoUsdaHttpTransport(),
    this.timeout = const Duration(seconds: 25),
  });

  final String apiKey;
  final UsdaHttpTransport transport;
  final Duration timeout;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  Uri searchUri() => Uri.parse(
    '$usdaBaseUrl/foods/search',
  ).replace(queryParameters: {'api_key': apiKey});

  String searchRequestBody(String query) => jsonEncode({
    'query': query,
    'pageSize': 10,
    'dataType': ['Foundation', 'SR Legacy', 'Survey (FNDDS)', 'Branded'],
  });

  Future<List<FoodAnalysisCandidate>> search(String query) async {
    if (!isConfigured) return const [];
    try {
      final response = await transport.send(
        method: 'POST',
        uri: searchUri(),
        headers: const {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.acceptHeader: 'application/json',
        },
        body: searchRequestBody(query),
        timeout: timeout,
      );
      _validateStatus(response.statusCode);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final foods = decoded['foods'] as List<dynamic>?;
      if (foods == null) {
        throw const FoodAnalysisException(FoodAnalysisErrorType.malformed);
      }
      if (foods.isEmpty) {
        throw const FoodAnalysisException(FoodAnalysisErrorType.noResults);
      }
      final candidates = foods
          .whereType<Map>()
          .map(
            (food) =>
                _candidateFromSearch(Map<String, dynamic>.from(food), query),
          )
          .where((candidate) => candidate.id > 0)
          .toList();
      if (candidates.isEmpty) {
        throw const FoodAnalysisException(FoodAnalysisErrorType.malformed);
      }
      candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
      return candidates;
    } on FoodAnalysisException {
      rethrow;
    } on TimeoutException {
      throw const FoodAnalysisException(FoodAnalysisErrorType.network);
    } on SocketException {
      throw const FoodAnalysisException(FoodAnalysisErrorType.network);
    } on FormatException {
      throw const FoodAnalysisException(FoodAnalysisErrorType.malformed);
    } catch (_) {
      throw const FoodAnalysisException(FoodAnalysisErrorType.unknown);
    }
  }

  Future<FoodAnalysisCandidate> getFood(int fdcId) async {
    if (!isConfigured) {
      throw const FoodAnalysisException(FoodAnalysisErrorType.unauthorized);
    }
    try {
      final uri = Uri.parse(
        '$usdaBaseUrl/food/$fdcId',
      ).replace(queryParameters: {'api_key': apiKey});
      final response = await transport.send(
        method: 'GET',
        uri: uri,
        headers: const {HttpHeaders.acceptHeader: 'application/json'},
        timeout: timeout,
      );
      _validateStatus(response.statusCode);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _candidateFromDetail(json);
    } on FoodAnalysisException {
      rethrow;
    } on TimeoutException {
      throw const FoodAnalysisException(FoodAnalysisErrorType.network);
    } on SocketException {
      throw const FoodAnalysisException(FoodAnalysisErrorType.network);
    } on FormatException {
      throw const FoodAnalysisException(FoodAnalysisErrorType.malformed);
    } catch (_) {
      throw const FoodAnalysisException(FoodAnalysisErrorType.unknown);
    }
  }

  static FoodAnalysisCandidate _candidateFromSearch(
    Map<String, dynamic> json,
    String query,
  ) {
    final nutrients = (json['foodNutrients'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final nutrition = extractNutrients(nutrients);
    final description = json['description'] as String? ?? '';
    final dataType = json['dataType'] as String? ?? '';
    return FoodAnalysisCandidate(
      id: json['fdcId'] as int? ?? 0,
      description: description,
      dataType: dataType,
      brandOwner: json['brandOwner'] as String?,
      servingSize: (json['servingSize'] as num?)?.toDouble(),
      servingSizeUnit: json['servingSizeUnit'] as String?,
      caloriesPer100g: nutrition.calories,
      proteinPer100g: nutrition.protein,
      carbsPer100g: nutrition.carbs,
      fatPer100g: nutrition.fat,
      matchScore: UsdaCandidateRanker.score(
        query: query,
        description: description,
        dataType: dataType,
        isBranded: (json['brandOwner'] as String?)?.isNotEmpty ?? false,
      ),
    );
  }

  static FoodAnalysisCandidate _candidateFromDetail(Map<String, dynamic> json) {
    final nutrientRows = (json['foodNutrients'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) {
          final map = Map<String, dynamic>.from(row);
          final nutrient = map['nutrient'] as Map?;
          if (nutrient != null) {
            map['nutrientId'] = nutrient['id'];
            map['nutrientName'] = nutrient['name'];
            map['unitName'] = nutrient['unitName'];
            map['value'] = map['amount'];
          }
          return map;
        })
        .toList();
    final nutrition = extractNutrients(nutrientRows);
    return FoodAnalysisCandidate(
      id: json['fdcId'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      dataType: json['dataType'] as String? ?? '',
      brandOwner: json['brandOwner'] as String?,
      servingSize: (json['servingSize'] as num?)?.toDouble(),
      servingSizeUnit: json['servingSizeUnit'] as String?,
      caloriesPer100g: nutrition.calories,
      proteinPer100g: nutrition.protein,
      carbsPer100g: nutrition.carbs,
      fatPer100g: nutrition.fat,
      matchScore: 0,
    );
  }

  static UsdaNutritionPer100g extractNutrients(
    List<Map<String, dynamic>> nutrients,
  ) {
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    for (final nutrient in nutrients) {
      final id = nutrient['nutrientId'] as int? ?? nutrient['id'] as int?;
      final name = (nutrient['nutrientName'] ?? nutrient['name'] ?? '')
          .toString()
          .toLowerCase();
      final unit = (nutrient['unitName'] ?? nutrient['unit'] ?? '')
          .toString()
          .toLowerCase();
      final value = (nutrient['value'] ?? nutrient['amount'] as num?) as num?;
      if (value == null) continue;
      final amount = value.toDouble();
      if (id == 1008 || name == 'energy' || name.contains('energy')) {
        final kcal = unit == 'kj' ? amount / 4.184 : amount;
        if (calories == 0 || unit == 'kcal') calories = kcal;
      } else if (id == 1003 || name == 'protein') {
        protein = amount;
      } else if (id == 1005 || name.contains('carbohydrate')) {
        carbs = amount;
      } else if (id == 1004 || name.contains('total lipid') || name == 'fat') {
        fat = amount;
      }
    }
    return UsdaNutritionPer100g(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
    );
  }

  static void _validateStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw FoodAnalysisException(switch (statusCode) {
      401 || 403 => FoodAnalysisErrorType.unauthorized,
      400 => FoodAnalysisErrorType.badRequest,
      429 => FoodAnalysisErrorType.rateLimited,
      >= 500 => FoodAnalysisErrorType.unavailable,
      _ => FoodAnalysisErrorType.unknown,
    });
  }
}

class UsdaNutritionPer100g {
  const UsdaNutritionPer100g({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
}

class UsdaCandidateRanker {
  const UsdaCandidateRanker._();

  static double score({
    required String query,
    required String description,
    required String dataType,
    required bool isBranded,
  }) {
    final q = query.toLowerCase();
    final d = description.toLowerCase();
    final queryTokens = q.split(RegExp(r'\s+')).where((t) => t.length > 2);
    var score = queryTokens.where(d.contains).length * 10.0;
    score += switch (dataType.toLowerCase()) {
      'foundation' => 30,
      'sr legacy' => 25,
      'survey (fndds)' => 18,
      'branded' => 0,
      _ => 5,
    };
    if (isBranded) score -= 12;
    if (q.contains('cooked')) {
      score += d.contains('cooked') ? 15 : -10;
      if (d.contains('raw')) score -= 25;
    }
    if (q.contains('raw')) {
      score += d.contains('raw') ? 12 : 0;
      if (d.contains('cooked')) score -= 12;
    }
    for (final excluded in _excludedWords) {
      if (!q.contains(excluded) && d.contains(excluded)) score -= 35;
    }
    return score;
  }

  static const _excludedWords = [
    'sandwich',
    'soup',
    'breaded',
    'baby food',
    'frozen meal',
    'restaurant',
    'pizza',
  ];
}
