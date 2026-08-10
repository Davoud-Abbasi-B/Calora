import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../features/nutrition/providers/today_journal_provider.dart';
import '../../features/nutrition/services/nutrition_day_reconciliation_service.dart';
import '../../features/settings/providers/calorie_targets_provider.dart';

class NutritionLifecycleReconciler extends ConsumerStatefulWidget {
  const NutritionLifecycleReconciler({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<NutritionLifecycleReconciler> createState() =>
      _NutritionLifecycleReconcilerState();
}

class _NutritionLifecycleReconcilerState
    extends ConsumerState<NutritionLifecycleReconciler>
    with WidgetsBindingObserver {
  Timer? _rolloverTimer;
  bool _isReconciling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRollover();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rolloverTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileAndReloadToday();
      _scheduleRollover();
    }
  }

  void _scheduleRollover() {
    _rolloverTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _rolloverTimer = Timer(
      nextDay.difference(now) + const Duration(seconds: 1),
      () async {
        await _reconcileAndReloadToday();
        _scheduleRollover();
      },
    );
  }

  Future<void> _reconcileAndReloadToday() async {
    if (_isReconciling || !mounted) return;
    final targets = ref.read(calorieTargetsProvider);
    if (targets == null) return;
    _isReconciling = true;
    try {
      final storage = ref.read(localStorageServiceProvider);
      final reconciliation = NutritionDayReconciliationService(
        storage: storage,
      );
      await reconciliation.snapshotTodayIfNeeded();
      await reconciliation.reconcile();
      if (!mounted) return;
      ref.read(historyProvider.notifier).refresh();
      await ref
          .read(todayJournalProvider.notifier)
          .loadDate(DateTime.now(), targets);
    } catch (_) {
      // A later resume or rollover retries reconciliation. Lifecycle callbacks
      // must not surface storage failures as uncaught asynchronous errors.
    } finally {
      _isReconciling = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
