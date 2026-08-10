import '../../../data/local/local_storage_service.dart';
import '../models/daily_nutrition_model.dart';
import '../models/food_analysis_result.dart';

class NutritionJournalService {
  const NutritionJournalService(this.storage);

  final LocalStorageService storage;

  List<DailyNutritionEntry> loadDraft(String dateKey) =>
      storage.loadDailyNutritionDraft(dateKey);

  Future<void> saveDraft(String dateKey, List<DailyNutritionEntry> entries) =>
      storage.saveDailyNutritionDraft(dateKey, entries);

  Future<DailyNutritionReport> finalize({
    required String dateKey,
    required NutritionDayType dayType,
    NutritionReportSubmissionType submissionType =
        NutritionReportSubmissionType.manual,
    int? targetCalories,
  }) => storage.finalizeDailyNutritionReport(
    dateKey: dateKey,
    dayType: dayType,
    submissionType: submissionType,
    targetCalories: targetCalories,
  );

  Future<ReopenTodayReportResult> reopenTodayReport({
    required String dateKey,
    DateTime? currentDate,
  }) async {
    final todayKey = nutritionDateKey(currentDate ?? DateTime.now());
    if (dateKey != todayKey) return ReopenTodayReportResult.notToday;

    final report = storage.loadDailyNutritionReport(dateKey);
    if (report == null) return ReopenTodayReportResult.alreadyOpen;
    if (report.submissionType != NutritionReportSubmissionType.manual) {
      return ReopenTodayReportResult.notManual;
    }

    if (storage.loadDailyNutritionMetadata(dateKey) == null &&
        report.targetCalories != null) {
      await storage.saveDailyNutritionMetadata(
        DailyNutritionMetadata(
          dateKey: dateKey,
          dayType: report.dayType,
          targetCalories: report.targetCalories!,
        ),
      );
    }
    await storage.removeDailyNutritionReport(dateKey);
    return ReopenTodayReportResult.reopened;
  }
}

enum ReopenTodayReportResult { reopened, alreadyOpen, notToday, notManual }

List<DailyNutritionEntry> dailyNutritionEntriesFromAnalyses(
  List<FoodAnalysisResult> results, {
  required String dateKey,
  DateTime? createdAt,
}) {
  final timestamp = createdAt ?? DateTime.now();
  return results.indexed
      .map(
        (indexed) => DailyNutritionEntry.fromAnalysis(
          result: indexed.$2,
          dateKey: dateKey,
          createdAt: timestamp.add(Duration(microseconds: indexed.$1)),
        ),
      )
      .toList(growable: false);
}
