import '../models/food_analysis_result.dart';

abstract interface class FoodAnalysisService {
  Future<FoodAnalysisBatchResult> analyze(String input);
}

class FoodNotRecognizedException implements Exception {
  const FoodNotRecognizedException();
}

enum FoodAnalysisErrorType {
  network,
  unauthorized,
  rateLimited,
  badRequest,
  unavailable,
  malformed,
  noResults,
  unknown,
}

class FoodAnalysisException implements Exception {
  const FoodAnalysisException(this.type);

  final FoodAnalysisErrorType type;
}

String foodAnalysisErrorMessage(Object error) {
  final type = error is FoodAnalysisException
      ? error.type
      : FoodAnalysisErrorType.unknown;
  return switch (type) {
    FoodAnalysisErrorType.network =>
      'ارتباط با پایگاه اطلاعات غذایی برقرار نشد.',
    FoodAnalysisErrorType.unauthorized =>
      'کلید پایگاه اطلاعات غذایی معتبر نیست.',
    FoodAnalysisErrorType.rateLimited =>
      'تعداد جست‌وجوها بیش از حد مجاز است. کمی بعد دوباره تلاش کنید.',
    FoodAnalysisErrorType.badRequest => 'درخواست محاسبه معتبر نبود.',
    FoodAnalysisErrorType.unavailable => 'سرویس محاسبه موقتاً در دسترس نیست.',
    FoodAnalysisErrorType.malformed =>
      'اطلاعات دریافتی از پایگاه غذایی قابل پردازش نبود.',
    FoodAnalysisErrorType.noResults => 'خوراکی مشابهی در پایگاه USDA پیدا نشد.',
    FoodAnalysisErrorType.unknown => 'در جست‌وجوی اطلاعات غذایی خطایی رخ داد.',
  };
}

bool validManualNutritionValues(Iterable<double?> values) {
  final list = values.toList(growable: false);
  return list.isNotEmpty &&
      list.every((value) => value != null && value >= 0) &&
      list.any((value) => value! > 0);
}
