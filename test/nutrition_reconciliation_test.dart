import 'dart:io';

import 'package:calorie_tracker/core/background/nutrition_background_work.dart';
import 'package:calorie_tracker/data/local/local_storage_service.dart';
import 'package:calorie_tracker/features/nutrition/models/daily_nutrition_model.dart';
import 'package:calorie_tracker/features/nutrition/models/food_analysis_result.dart';
import 'package:calorie_tracker/features/nutrition/providers/today_journal_provider.dart';
import 'package:calorie_tracker/features/nutrition/services/nutrition_day_reconciliation_service.dart';
import 'package:calorie_tracker/features/nutrition/services/nutrition_journal_service.dart';
import 'package:calorie_tracker/features/settings/models/calorie_targets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box<dynamic> box;
  late LocalStorageService storage;
  late NutritionDayReconciliationService reconciliation;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reconciliation_test_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      'reconcile_${DateTime.now().microsecondsSinceEpoch}',
    );
    storage = LocalStorageService(box);
    await storage.saveCalorieTargets(_targets);
    reconciliation = NutritionDayReconciliationService(
      storage: storage,
      now: () => DateTime(2026, 8, 11, 0, 1),
    );
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await directory.delete(recursive: true);
  });

  test('past draft with entries auto-finalizes with its snapshot', () async {
    await _seedDay(
      storage,
      '2026-08-10',
      type: NutritionDayType.training,
      target: 2000,
    );

    final result = await reconciliation.reconcile();
    final report = storage.loadDailyNutritionReport('2026-08-10');

    expect(result.finalizedDateKeys, ['2026-08-10']);
    expect(report?.submissionType, NutritionReportSubmissionType.automatic);
    expect(report?.dayType, NutritionDayType.training);
    expect(report?.targetCalories, 2000);
    expect(report?.totalCalories, 500);
  });

  test('empty past draft does not auto-finalize', () async {
    await storage.saveDailyNutritionDraft('2026-08-10', const []);
    await storage.saveDailyNutritionMetadata(
      const DailyNutritionMetadata(
        dateKey: '2026-08-10',
        dayType: NutritionDayType.training,
        targetCalories: 2000,
      ),
    );

    expect((await reconciliation.reconcile()).finalizedCount, 0);
    expect(storage.loadDailyNutritionReport('2026-08-10'), isNull);
  });

  test('already finalized manual date is skipped and never replaced', () async {
    await _seedDay(
      storage,
      '2026-08-10',
      type: NutritionDayType.rest,
      target: 1800,
    );
    final manual = await storage.finalizeDailyNutritionReport(
      dateKey: '2026-08-10',
      dayType: NutritionDayType.rest,
      submissionType: NutritionReportSubmissionType.manual,
      targetCalories: 1800,
      submittedAt: DateTime(2026, 8, 10, 22),
    );

    expect((await reconciliation.reconcile()).finalizedCount, 0);
    final stored = storage.loadDailyNutritionReport('2026-08-10');
    expect(stored?.submittedAt, manual.submittedAt);
    expect(stored?.submissionType, NutritionReportSubmissionType.manual);
  });

  test('multiple forgotten dates reconcile independently', () async {
    await _seedDay(
      storage,
      '2026-08-07',
      type: NutritionDayType.training,
      target: 2000,
    );
    await _seedDay(
      storage,
      '2026-08-09',
      type: NutritionDayType.rest,
      target: 1800,
    );
    await storage.saveDailyNutritionDraft('2026-08-08', const []);

    final result = await reconciliation.reconcile();

    expect(result.finalizedDateKeys, ['2026-08-07', '2026-08-09']);
    expect(storage.loadDailyNutritionReports(), hasLength(2));
  });

  test('reconciliation is idempotent across repeated runs', () async {
    await _seedDay(
      storage,
      '2026-08-10',
      type: NutritionDayType.training,
      target: 2000,
    );

    expect((await reconciliation.reconcile()).finalizedCount, 1);
    expect((await reconciliation.reconcile()).finalizedCount, 0);
    expect(storage.loadDailyNutritionReports(), hasLength(1));
  });

  test(
    'global target change does not alter a snapshotted forgotten day',
    () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.training,
        target: 2000,
      );
      await storage.saveCalorieTargets(
        const CalorieTargets(trainingDayCalories: 2200, restDayCalories: 1900),
      );

      await reconciliation.reconcile();

      expect(
        storage.loadDailyNutritionReport('2026-08-10')?.targetCalories,
        2000,
      );
    },
  );

  test('legacy draft uses documented current-target fallback', () async {
    await storage.saveDailyNutritionDraft('2026-08-10', [_entry('legacy')]);
    await storage.saveDayType('2026-08-10', NutritionDayType.rest);

    await reconciliation.reconcile();

    final report = storage.loadDailyNutritionReport('2026-08-10');
    expect(report?.targetCalories, 1800);
    expect(
      storage.loadDailyNutritionMetadata('2026-08-10')?.targetCalories,
      1800,
    );
  });

  test('legacy current day snapshots before later settings changes', () async {
    await storage.saveDayType('2026-08-11', NutritionDayType.training);

    final metadata = await reconciliation.snapshotTodayIfNeeded();
    await storage.saveCalorieTargets(
      const CalorieTargets(trainingDayCalories: 2200, restDayCalories: 1900),
    );

    expect(metadata?.targetCalories, 2000);
    expect(
      storage.loadDailyNutritionMetadata('2026-08-11')?.targetCalories,
      2000,
    );
  });

  test(
    'changing day type before finalization updates target snapshot',
    () async {
      final notifier = TodayJournalNotifier(
        storage: storage,
        journal: NutritionJournalService(storage),
        dateKey: '2026-08-10',
        targets: _targets,
      );
      addTearDown(notifier.dispose);

      await notifier.selectDayType(NutritionDayType.training, _targets);
      expect(notifier.state.targetCalories, 2000);
      await notifier.selectDayType(NutritionDayType.rest, _targets);

      expect(notifier.state.targetCalories, 1800);
      final metadata = storage.loadDailyNutritionMetadata('2026-08-10');
      expect(metadata?.dayType, NutritionDayType.rest);
      expect(metadata?.targetCalories, 1800);
    },
  );

  test(
    'finalized report remains immutable after settings and type attempts',
    () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.training,
        target: 2000,
      );
      final notifier = TodayJournalNotifier(
        storage: storage,
        journal: NutritionJournalService(storage),
        dateKey: '2026-08-10',
        targets: _targets,
      );
      addTearDown(notifier.dispose);
      await notifier.finishDay();
      await storage.saveCalorieTargets(
        const CalorieTargets(trainingDayCalories: 2400, restDayCalories: 2100),
      );
      await notifier.selectDayType(
        NutritionDayType.rest,
        const CalorieTargets(trainingDayCalories: 2400, restDayCalories: 2100),
      );

      final report = storage.loadDailyNutritionReport('2026-08-10');
      expect(report?.dayType, NutritionDayType.training);
      expect(report?.targetCalories, 2000);
    },
  );

  group('reopen today', () {
    test(
      'manual report reopens with draft, day type, and target preserved',
      () async {
        await _seedDay(
          storage,
          '2026-08-10',
          type: NutritionDayType.training,
          target: 2000,
        );
        final notifier = TodayJournalNotifier(
          storage: storage,
          journal: NutritionJournalService(storage),
          dateKey: '2026-08-10',
          targets: _targets,
          now: () => DateTime(2026, 8, 10, 20),
        );
        addTearDown(notifier.dispose);
        await notifier.finishDay();

        expect(notifier.state.isFinalized, isTrue);
        expect(await notifier.reopenToday(), ReopenTodayReportResult.reopened);

        expect(storage.loadDailyNutritionReport('2026-08-10'), isNull);
        expect(storage.loadDailyNutritionDraft('2026-08-10'), hasLength(1));
        expect(notifier.state.isFinalized, isFalse);
        expect(notifier.state.entries, hasLength(1));
        expect(notifier.state.dayType, NutritionDayType.training);
        expect(notifier.state.targetCalories, 2000);
      },
    );

    test('edited day re-finalizes once with updated totals', () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.rest,
        target: 1800,
      );
      final notifier = TodayJournalNotifier(
        storage: storage,
        journal: NutritionJournalService(storage),
        dateKey: '2026-08-10',
        targets: _targets,
        now: () => DateTime(2026, 8, 10, 20),
      );
      addTearDown(notifier.dispose);
      await notifier.finishDay();
      await notifier.reopenToday();

      await notifier.deleteEntry('2026-08-10');
      expect(notifier.state.entries, isEmpty);
      await notifier.addAnalysisItems([_analysis(calories: 275)]);
      final report = await notifier.finishDay();
      final duplicate = await notifier.finishDay();

      expect(storage.loadDailyNutritionReports(), hasLength(1));
      expect(report.totalCalories, 275);
      expect(duplicate.submittedAt, report.submittedAt);
      expect(report.submissionType, NutritionReportSubmissionType.manual);
      expect(report.dayType, NutritionDayType.rest);
      expect(report.targetCalories, 1800);
    });

    test('past manual report cannot be reopened', () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.training,
        target: 2000,
      );
      await storage.finalizeDailyNutritionReport(
        dateKey: '2026-08-10',
        dayType: NutritionDayType.training,
        targetCalories: 2000,
      );
      final service = NutritionJournalService(storage);

      expect(
        await service.reopenTodayReport(
          dateKey: '2026-08-10',
          currentDate: DateTime(2026, 8, 11),
        ),
        ReopenTodayReportResult.notToday,
      );
      expect(storage.loadDailyNutritionReport('2026-08-10'), isNotNull);
    });

    test('automatically finalized report cannot be reopened', () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.training,
        target: 2000,
      );
      await storage.finalizeDailyNutritionReport(
        dateKey: '2026-08-10',
        dayType: NutritionDayType.training,
        submissionType: NutritionReportSubmissionType.automatic,
        targetCalories: 2000,
      );

      expect(
        await NutritionJournalService(storage).reopenTodayReport(
          dateKey: '2026-08-10',
          currentDate: DateTime(2026, 8, 10),
        ),
        ReopenTodayReportResult.notManual,
      );
      expect(storage.loadDailyNutritionReport('2026-08-10'), isNotNull);
    });

    test('repeated reopen is safe and idempotent', () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.training,
        target: 2000,
      );
      await storage.finalizeDailyNutritionReport(
        dateKey: '2026-08-10',
        dayType: NutritionDayType.training,
        targetCalories: 2000,
      );
      final service = NutritionJournalService(storage);

      expect(
        await service.reopenTodayReport(
          dateKey: '2026-08-10',
          currentDate: DateTime(2026, 8, 10),
        ),
        ReopenTodayReportResult.reopened,
      );
      expect(
        await service.reopenTodayReport(
          dateKey: '2026-08-10',
          currentDate: DateTime(2026, 8, 10),
        ),
        ReopenTodayReportResult.alreadyOpen,
      );
      expect(storage.loadDailyNutritionDraft('2026-08-10'), hasLength(1));
    });

    test('unfinished reopened draft auto-finalizes after rollover', () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.training,
        target: 2000,
      );
      await storage.finalizeDailyNutritionReport(
        dateKey: '2026-08-10',
        dayType: NutritionDayType.training,
        targetCalories: 2000,
      );
      await NutritionJournalService(storage).reopenTodayReport(
        dateKey: '2026-08-10',
        currentDate: DateTime(2026, 8, 10, 23, 30),
      );

      final result = await reconciliation.reconcile();
      final report = storage.loadDailyNutritionReport('2026-08-10');

      expect(result.finalizedDateKeys, ['2026-08-10']);
      expect(report?.submissionType, NutritionReportSubmissionType.automatic);
      expect(report?.totalCalories, 500);
      expect(report?.targetCalories, 2000);
    });
  });

  test('date rollover loads an independent new Today state', () async {
    await _seedDay(
      storage,
      '2026-08-10',
      type: NutritionDayType.training,
      target: 2000,
    );
    final notifier = TodayJournalNotifier(
      storage: storage,
      journal: NutritionJournalService(storage),
      dateKey: '2026-08-10',
      targets: _targets,
    );
    addTearDown(notifier.dispose);

    await notifier.loadDate(DateTime(2026, 8, 11, 0, 1), _targets);

    expect(notifier.state.dateKey, '2026-08-11');
    expect(notifier.state.entries, isEmpty);
    expect(notifier.state.dayType, isNull);
    expect(notifier.state.targetCalories, isNull);
  });

  test(
    'background entry initializes only supplied local storage safely',
    () async {
      await _seedDay(
        storage,
        '2026-08-10',
        type: NutritionDayType.training,
        target: 2000,
      );
      var initializationCalls = 0;

      final result = await runBackgroundNutritionReconciliation(
        initializeStorage: () async {
          initializationCalls++;
          return storage;
        },
        now: () => DateTime(2026, 8, 11, 0, 1),
      );

      expect(initializationCalls, 1);
      expect(result.finalizedCount, 1);
    },
  );

  test('midnight scheduling delay targets shortly after next rollover', () {
    expect(
      durationUntilNextReconciliation(DateTime(2026, 8, 10, 23, 59)),
      const Duration(minutes: 11),
    );
    expect(
      durationUntilNextReconciliation(DateTime(2026, 8, 11, 0, 1)),
      const Duration(hours: 24, minutes: 9),
    );
  });
}

const _targets = CalorieTargets(
  trainingDayCalories: 2000,
  restDayCalories: 1800,
);

Future<void> _seedDay(
  LocalStorageService storage,
  String dateKey, {
  required NutritionDayType type,
  required int target,
}) async {
  await storage.saveDailyNutritionDraft(dateKey, [_entry(dateKey)]);
  await storage.saveDailyNutritionMetadata(
    DailyNutritionMetadata(
      dateKey: dateKey,
      dayType: type,
      targetCalories: target,
    ),
  );
}

DailyNutritionEntry _entry(String id) => DailyNutritionEntry(
  id: id,
  dateKey: id,
  createdAt: DateTime(2026, 8, 10, 12),
  originalInput: 'غذا',
  foodName: 'غذا',
  quantityText: '۱ وعده',
  calories: 500,
  proteinGrams: 20,
  carbsGrams: 50,
  fatGrams: 15,
  isEstimated: false,
);

FoodAnalysisResult _analysis({required double calories}) => FoodAnalysisResult(
  originalInput: 'غذای ویرایش‌شده',
  foodName: 'غذای ویرایش‌شده',
  quantityText: '۱ وعده',
  calories: calories,
  proteinGrams: 25,
  carbsGrams: 30,
  fatGrams: 8,
  isEstimated: false,
);
