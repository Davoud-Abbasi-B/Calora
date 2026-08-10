import 'dart:io';

import 'package:calorie_tracker/app.dart';
import 'package:calorie_tracker/data/local/local_storage_service.dart';
import 'package:calorie_tracker/features/nutrition/models/daily_nutrition_model.dart';
import 'package:calorie_tracker/features/nutrition/models/food_analysis_result.dart';
import 'package:calorie_tracker/features/nutrition/providers/today_journal_provider.dart';
import 'package:calorie_tracker/features/nutrition/services/nutrition_journal_service.dart';
import 'package:calorie_tracker/features/settings/models/calorie_targets.dart';
import 'package:calorie_tracker/features/settings/providers/calorie_targets_provider.dart';
import 'package:calorie_tracker/features/settings/widgets/calorie_targets_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  testWidgets('startup routes directly without a Flutter branded splash', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [calorieTargetsProvider.overrideWith(_NoTargets.new)],
        child: const CalorieTrackerApp(),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'BrandedSplashScreen',
      ),
      findsNothing,
    );
    expect(find.text('هدف کالری روزانه'), findsOneWidget);
  });

  testWidgets('Material app uses the Calora brand title', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [calorieTargetsProvider.overrideWith(_NoTargets.new)],
        child: const CalorieTrackerApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, appTitle);
    expect(app.title, 'Calora');
  });

  testWidgets('first launch without targets shows onboarding', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [calorieTargetsProvider.overrideWith(_NoTargets.new)],
        child: const CalorieTrackerApp(),
      ),
    );
    await tester.pump();
    expect(find.text('هدف کالری روزانه'), findsOneWidget);
    expect(find.text('شروع'), findsOneWidget);
  });

  testWidgets(
    'target form rejects invalid values and recovers after save error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CalorieTargetsForm(
                buttonLabel: 'ذخیره',
                onSave: (_) async => throw StateError('storage failed'),
              ),
            ),
          ),
        ),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '-10');
      await tester.enterText(fields.at(1), '۲۰۰۰۱');
      await tester.tap(find.text('ذخیره'));
      await tester.pump();
      expect(
        find.text('مقدار معتبر بین ۱ تا ۲۰۰۰۰ وارد کنید.'),
        findsNWidgets(2),
      );

      await tester.enterText(fields.at(0), '۲۴۰۰');
      await tester.enterText(fields.at(1), '۱۹۰۰');
      await tester.tap(find.text('ذخیره'));
      await tester.pump();
      expect(
        find.text('ذخیره هدف‌ها ممکن نشد. دوباره تلاش کنید.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    },
  );

  test('training and rest selections use their corresponding targets', () {
    const targets = CalorieTargets(
      trainingDayCalories: 2400,
      restDayCalories: 1900,
    );
    expect(calorieTargetForDay(targets, NutritionDayType.training), 2400);
    expect(calorieTargetForDay(targets, NutritionDayType.rest), 1900);
  });

  group('today journal', () {
    late Directory directory;
    late Box<dynamic> box;
    late LocalStorageService storage;
    late TodayJournalNotifier notifier;
    const key = '2026-08-10';

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('journal_state_test_');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>(
        'journal_${DateTime.now().microsecondsSinceEpoch}',
      );
      storage = LocalStorageService(box);
      notifier = TodayJournalNotifier(
        storage: storage,
        journal: NutritionJournalService(storage),
        dateKey: key,
      );
    });

    tearDown(() async {
      notifier.dispose();
      await box.deleteFromDisk();
      await directory.delete(recursive: true);
    });

    test('adding and deleting food immediately updates totals', () async {
      await notifier.addAnalysisItems([_food()]);
      expect(notifier.state.totals.calories, 70);
      expect(notifier.state.totals.proteinGrams, 6);
      final id = notifier.state.entries.single.id;

      await notifier.deleteEntry(id);

      expect(notifier.state.entries, isEmpty);
      expect(notifier.state.totals.calories, 0);
    });

    test('cannot finalize an empty day', () async {
      await notifier.selectDayType(NutritionDayType.training, _targets);
      await expectLater(
        notifier.finishDay(),
        throwsA(isA<JournalActionException>()),
      );
      expect(storage.loadDailyNutritionReports(), isEmpty);
    });

    test('manual finalization is idempotent and captures target', () async {
      await notifier.selectDayType(NutritionDayType.training, _targets);
      await notifier.addAnalysisItems([_food()]);

      final first = await notifier.finishDay();
      final second = await notifier.finishDay();

      expect(storage.loadDailyNutritionReports(), hasLength(1));
      expect(second.submittedAt, first.submittedAt);
      expect(first.submissionType, NutritionReportSubmissionType.manual);
      expect(first.targetCalories, 2400);
    });

    test(
      'rapid draft deletions are serialized without losing either edit',
      () async {
        await notifier.addAnalysisItems([_food(), _food(), _food()]);
        final ids = notifier.state.entries.map((entry) => entry.id).toList();

        await Future.wait([
          notifier.deleteEntry(ids[0]),
          notifier.deleteEntry(ids[1]),
        ]);

        expect(notifier.state.entries.map((entry) => entry.id), [ids[2]]);
        expect(storage.loadDailyNutritionDraft(key), hasLength(1));
      },
    );

    test('concurrent finalization shares one report operation', () async {
      await notifier.selectDayType(NutritionDayType.training, _targets);
      await notifier.addAnalysisItems([_food()]);

      final reports = await Future.wait([
        notifier.finishDay(),
        notifier.finishDay(),
      ]);

      expect(identical(reports[0], reports[1]), isTrue);
      expect(storage.loadDailyNutritionReports(), hasLength(1));
    });

    test(
      'history is newest first and target changes do not mutate reports',
      () async {
        await storage.saveDailyNutritionDraft('2026-08-09', [_entry('old')]);
        await storage.finalizeDailyNutritionReport(
          dateKey: '2026-08-09',
          dayType: NutritionDayType.rest,
          targetCalories: 1900,
        );
        await storage.saveDailyNutritionDraft('2026-08-10', [_entry('new')]);
        await storage.finalizeDailyNutritionReport(
          dateKey: '2026-08-10',
          dayType: NutritionDayType.training,
          targetCalories: 2400,
        );

        expect(
          storage.loadDailyNutritionReports().map((report) => report.dateKey),
          ['2026-08-10', '2026-08-09'],
        );
        await storage.saveCalorieTargets(
          const CalorieTargets(
            trainingDayCalories: 3000,
            restDayCalories: 2500,
          ),
        );
        expect(
          storage.loadDailyNutritionReport('2026-08-10')?.targetCalories,
          2400,
        );
      },
    );
  });
}

const _targets = CalorieTargets(
  trainingDayCalories: 2400,
  restDayCalories: 1900,
);

FoodAnalysisResult _food() => const FoodAnalysisResult(
  originalInput: '۱ عدد تخم‌مرغ',
  foodName: 'تخم‌مرغ',
  quantityText: '۱ عدد',
  calories: 70,
  proteinGrams: 6,
  carbsGrams: 0.5,
  fatGrams: 5,
  isEstimated: true,
);

DailyNutritionEntry _entry(String id) => DailyNutritionEntry(
  id: id,
  dateKey: '2026-08-10',
  createdAt: DateTime(2026, 8, 10),
  originalInput: 'غذا',
  foodName: 'غذا',
  quantityText: '۱ عدد',
  calories: 100,
  proteinGrams: 1,
  carbsGrams: 1,
  fatGrams: 1,
  isEstimated: true,
);

class _NoTargets extends CalorieTargetsNotifier {
  @override
  CalorieTargets? build() => null;
}
