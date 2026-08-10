import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../data/local/local_storage_service.dart';
import '../../settings/models/calorie_targets.dart';
import '../../settings/providers/calorie_targets_provider.dart';
import '../models/daily_nutrition_model.dart';
import '../models/food_analysis_result.dart';
import '../services/nutrition_journal_service.dart';

class TodayJournalState {
  const TodayJournalState({
    required this.dateKey,
    required this.dayType,
    required this.entries,
    required this.report,
    required this.targetCalories,
  });

  final String dateKey;
  final NutritionDayType? dayType;
  final List<DailyNutritionEntry> entries;
  final DailyNutritionReport? report;
  final int? targetCalories;

  bool get isFinalized => report != null;
  List<DailyNutritionEntry> get visibleEntries => report?.entries ?? entries;
  DailyNutritionTotals get totals =>
      DailyNutritionTotals.fromEntries(visibleEntries);

  TodayJournalState copyWith({
    NutritionDayType? dayType,
    List<DailyNutritionEntry>? entries,
    DailyNutritionReport? report,
    int? targetCalories,
  }) => TodayJournalState(
    dateKey: dateKey,
    dayType: dayType ?? this.dayType,
    entries: entries ?? this.entries,
    report: report ?? this.report,
    targetCalories: targetCalories ?? this.targetCalories,
  );
}

class TodayJournalNotifier extends StateNotifier<TodayJournalState> {
  TodayJournalNotifier({
    required this.storage,
    required this.journal,
    required String dateKey,
    CalorieTargets? targets,
    this.onFinalized,
    this.onReopened,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       super(_loadState(storage, dateKey, targets));

  final LocalStorageService storage;
  final NutritionJournalService journal;
  final void Function()? onFinalized;
  final void Function()? onReopened;
  final DateTime Function() now;
  Future<void> _draftMutation = Future<void>.value();
  Future<DailyNutritionReport>? _finishInFlight;
  Future<ReopenTodayReportResult>? _reopenInFlight;

  Future<void> selectDayType(NutritionDayType value, CalorieTargets targets) =>
      _queueDraftMutation(() async {
        if (state.isFinalized) return;
        final target = calorieTargetForDay(targets, value);
        await storage.saveDailyNutritionMetadata(
          DailyNutritionMetadata(
            dateKey: state.dateKey,
            dayType: value,
            targetCalories: target,
          ),
        );
        state = state.copyWith(dayType: value, targetCalories: target);
      });

  Future<void> addAnalysisItems(List<FoodAnalysisResult> results) =>
      _queueDraftMutation(() async {
        if (state.isFinalized || results.isEmpty) return;
        final additions = dailyNutritionEntriesFromAnalyses(
          results,
          dateKey: state.dateKey,
        );
        final entries = [...state.entries, ...additions];
        await journal.saveDraft(state.dateKey, entries);
        state = state.copyWith(entries: List.unmodifiable(entries));
      });

  Future<void> deleteEntry(String id) => _queueDraftMutation(() async {
    if (state.isFinalized) return;
    final entries = state.entries.where((entry) => entry.id != id).toList();
    await journal.saveDraft(state.dateKey, entries);
    state = state.copyWith(entries: List.unmodifiable(entries));
  });

  Future<DailyNutritionReport> finishDay() {
    final pending = _finishInFlight;
    if (pending != null) return pending;
    final operation = _finishDay();
    _finishInFlight = operation;
    operation.then<void>(
      (_) => _clearFinish(operation),
      onError: (_, _) => _clearFinish(operation),
    );
    return operation;
  }

  Future<DailyNutritionReport> _finishDay() async {
    await _draftMutation;
    final existing = state.report;
    if (existing != null) return existing;
    if (state.entries.isEmpty) {
      throw const JournalActionException(
        'برای ثبت روز، ابتدا یک خوراکی اضافه کنید.',
      );
    }
    final type = state.dayType;
    if (type == null) {
      throw const JournalActionException('ابتدا نوع روز را انتخاب کنید.');
    }
    final target = state.targetCalories;
    if (target == null) {
      throw const JournalActionException('هدف کالری این روز مشخص نیست.');
    }
    final report = await journal.finalize(
      dateKey: state.dateKey,
      dayType: type,
      submissionType: NutritionReportSubmissionType.manual,
      targetCalories: target,
    );
    state = state.copyWith(report: report);
    onFinalized?.call();
    return report;
  }

  Future<ReopenTodayReportResult> reopenToday() {
    final pending = _reopenInFlight;
    if (pending != null) return pending;
    final operation = _reopenToday();
    _reopenInFlight = operation;
    operation.then<void>(
      (_) => _clearReopen(operation),
      onError: (_, _) => _clearReopen(operation),
    );
    return operation;
  }

  Future<ReopenTodayReportResult> _reopenToday() async {
    await _draftMutation;
    final result = await journal.reopenTodayReport(
      dateKey: state.dateKey,
      currentDate: now(),
    );
    if (result == ReopenTodayReportResult.reopened ||
        result == ReopenTodayReportResult.alreadyOpen) {
      state = _loadState(storage, state.dateKey, null);
      onReopened?.call();
    }
    return result;
  }

  Future<void> loadDate(DateTime date, CalorieTargets targets) async {
    await _draftMutation;
    final key = nutritionDateKey(date);
    if (key == state.dateKey) return;
    state = _loadState(storage, key, targets);
    final type = state.dayType;
    if (!state.isFinalized && type != null && state.targetCalories == null) {
      await selectDayType(type, targets);
    }
  }

  Future<void> _queueDraftMutation(Future<void> Function() mutation) {
    final operation = _draftMutation.then((_) => mutation());
    _draftMutation = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  void _clearFinish(Future<DailyNutritionReport> operation) {
    if (identical(_finishInFlight, operation)) _finishInFlight = null;
  }

  void _clearReopen(Future<ReopenTodayReportResult> operation) {
    if (identical(_reopenInFlight, operation)) _reopenInFlight = null;
  }
}

TodayJournalState _loadState(
  LocalStorageService storage,
  String dateKey,
  CalorieTargets? targets,
) {
  final report = storage.loadDailyNutritionReport(dateKey);
  final metadata = storage.loadDailyNutritionMetadata(dateKey);
  final type =
      metadata?.dayType ?? storage.loadDayType(dateKey) ?? report?.dayType;
  return TodayJournalState(
    dateKey: dateKey,
    dayType: type,
    entries: storage.loadDailyNutritionDraft(dateKey),
    report: report,
    targetCalories:
        report?.targetCalories ??
        metadata?.targetCalories ??
        _legacyTarget(type, targets),
  );
}

class JournalActionException implements Exception {
  const JournalActionException(this.message);
  final String message;
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<DailyNutritionReport>>((ref) {
      return HistoryNotifier(ref.watch(localStorageServiceProvider));
    });

class HistoryNotifier extends StateNotifier<List<DailyNutritionReport>> {
  HistoryNotifier(this.storage) : super(storage.loadDailyNutritionReports());
  final LocalStorageService storage;

  void refresh() => state = storage.loadDailyNutritionReports();
}

final todayJournalProvider =
    StateNotifierProvider<TodayJournalNotifier, TodayJournalState>((ref) {
      final storage = ref.watch(localStorageServiceProvider);
      final targets = ref.watch(calorieTargetsProvider);
      return TodayJournalNotifier(
        storage: storage,
        journal: NutritionJournalService(storage),
        dateKey: nutritionDateKey(DateTime.now()),
        targets: targets,
        onFinalized: () => ref.read(historyProvider.notifier).refresh(),
        onReopened: () => ref.read(historyProvider.notifier).refresh(),
      );
    });

int calorieTargetForDay(CalorieTargets targets, NutritionDayType dayType) =>
    switch (dayType) {
      NutritionDayType.training => targets.trainingDayCalories,
      NutritionDayType.rest => targets.restDayCalories,
    };

int? _legacyTarget(NutritionDayType? type, CalorieTargets? targets) {
  if (type == null || targets == null) return null;
  return calorieTargetForDay(targets, type);
}
