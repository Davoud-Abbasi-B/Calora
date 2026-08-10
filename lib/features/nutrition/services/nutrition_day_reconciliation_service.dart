import '../../../data/local/local_storage_service.dart';
import '../../settings/models/calorie_targets.dart';
import '../models/daily_nutrition_model.dart';

class NutritionReconciliationResult {
  const NutritionReconciliationResult(this.finalizedDateKeys);

  final List<String> finalizedDateKeys;
  int get finalizedCount => finalizedDateKeys.length;
}

class NutritionDayReconciliationService {
  NutritionDayReconciliationService({
    required this.storage,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final LocalStorageService storage;
  final DateTime Function() now;

  Future<DailyNutritionMetadata?> snapshotTodayIfNeeded() =>
      snapshotDateIfNeeded(nutritionDateKey(now()));

  Future<DailyNutritionMetadata?> snapshotDateIfNeeded(String dateKey) async {
    final existing = storage.loadDailyNutritionMetadata(dateKey);
    if (existing != null) return existing;
    if (storage.loadDailyNutritionReport(dateKey) != null) return null;
    final dayType = storage.loadDayType(dateKey);
    final target = dayType == null
        ? null
        : _targetForLegacyDraft(storage.loadCalorieTargets(), dayType);
    if (dayType == null || target == null || target <= 0) return null;
    final metadata = DailyNutritionMetadata(
      dateKey: dateKey,
      dayType: dayType,
      targetCalories: target,
    );
    await storage.saveDailyNutritionMetadata(metadata);
    return metadata;
  }

  Future<NutritionReconciliationResult> reconcile() async {
    final todayKey = nutritionDateKey(now());
    final targets = storage.loadCalorieTargets();
    final finalized = <String>[];
    final draftKeys = storage.loadDailyNutritionDraftDateKeys()..sort();

    for (final dateKey in draftKeys) {
      if (dateKey.compareTo(todayKey) >= 0) continue;
      if (storage.loadDailyNutritionReport(dateKey) != null) continue;
      final entries = storage.loadDailyNutritionDraft(dateKey);
      if (entries.isEmpty) continue;

      final metadata =
          storage.loadDailyNutritionMetadata(dateKey) ??
          await snapshotDateIfNeeded(dateKey);
      final dayType = metadata?.dayType ?? storage.loadDayType(dateKey);
      if (dayType == null) continue;

      // Legacy drafts may predate per-day target snapshots. Their only
      // recoverable fallback is the currently configured target.
      final target =
          metadata?.targetCalories ?? _targetForLegacyDraft(targets, dayType);
      if (target == null || target <= 0) continue;

      if (metadata?.targetCalories == null) {
        await storage.saveDailyNutritionMetadata(
          DailyNutritionMetadata(
            dateKey: dateKey,
            dayType: dayType,
            targetCalories: target,
          ),
        );
      }
      final report = await storage.finalizeDailyNutritionReport(
        dateKey: dateKey,
        dayType: dayType,
        submissionType: NutritionReportSubmissionType.automatic,
        targetCalories: target,
        submittedAt: now(),
      );
      if (report.submissionType == NutritionReportSubmissionType.automatic) {
        finalized.add(dateKey);
      }
    }
    return NutritionReconciliationResult(List.unmodifiable(finalized));
  }
}

int? _targetForLegacyDraft(CalorieTargets? targets, NutritionDayType dayType) {
  if (targets == null) return null;
  return switch (dayType) {
    NutritionDayType.training => targets.trainingDayCalories,
    NutritionDayType.rest => targets.restDayCalories,
  };
}
