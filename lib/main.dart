import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/background/nutrition_background_work.dart';
import 'data/local/local_storage_service.dart';
import 'features/nutrition/services/nutrition_day_reconciliation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeApplication();
  runApp(const ProviderScope(child: CalorieTrackerApp()));
}

Future<void> _initializeApplication() async {
  final storage = await LocalStorageService.initialize();
  await initializeDateFormatting('fa');
  final reconciliation = NutritionDayReconciliationService(storage: storage);
  await reconciliation.snapshotTodayIfNeeded();
  await reconciliation.reconcile();
  try {
    await WorkmanagerNutritionBackgroundScheduler().initializeAndSchedule();
  } catch (_) {
    // Foreground reconciliation remains authoritative if scheduling fails.
  }
}
