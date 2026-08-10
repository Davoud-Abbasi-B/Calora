import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/local/local_storage_service.dart';
import '../../features/nutrition/services/nutrition_day_reconciliation_service.dart';

const nutritionReconciliationTask = 'nutrition_day_reconciliation';
const nutritionReconciliationUniqueWork =
    'calorie_tracker.daily_nutrition_reconciliation';

abstract interface class NutritionBackgroundScheduler {
  Future<void> initializeAndSchedule();
}

class WorkmanagerNutritionBackgroundScheduler
    implements NutritionBackgroundScheduler {
  WorkmanagerNutritionBackgroundScheduler({
    Workmanager? workmanager,
    DateTime Function()? now,
  }) : _workmanager = workmanager ?? Workmanager(),
       _now = now ?? DateTime.now;

  final Workmanager _workmanager;
  final DateTime Function() _now;

  @override
  Future<void> initializeAndSchedule() async {
    if (!Platform.isAndroid) return;
    await _workmanager.initialize(nutritionBackgroundCallbackDispatcher);
    await _workmanager.registerPeriodicTask(
      nutritionReconciliationUniqueWork,
      nutritionReconciliationTask,
      frequency: const Duration(hours: 24),
      initialDelay: durationUntilNextReconciliation(_now()),
      constraints: Constraints(networkType: NetworkType.notRequired),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}

Duration durationUntilNextReconciliation(DateTime now) {
  final nextRun = DateTime(now.year, now.month, now.day + 1, 0, 10);
  return nextRun.difference(now);
}

@pragma('vm:entry-point')
void nutritionBackgroundCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, _) async {
    if (task != nutritionReconciliationTask) return true;
    try {
      await runBackgroundNutritionReconciliation();
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<NutritionReconciliationResult> runBackgroundNutritionReconciliation({
  Future<LocalStorageService> Function()? initializeStorage,
  DateTime Function()? now,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await (initializeStorage ?? LocalStorageService.initialize)();
  return NutritionDayReconciliationService(
    storage: storage,
    now: now,
  ).reconcile();
}
