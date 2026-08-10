import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../models/calorie_targets.dart';

final calorieTargetsProvider =
    NotifierProvider<CalorieTargetsNotifier, CalorieTargets?>(
      CalorieTargetsNotifier.new,
    );

class CalorieTargetsNotifier extends Notifier<CalorieTargets?> {
  @override
  CalorieTargets? build() =>
      ref.watch(localStorageServiceProvider).loadCalorieTargets();

  Future<void> save(CalorieTargets targets) async {
    await ref.read(localStorageServiceProvider).saveCalorieTargets(targets);
    state = targets;
  }
}
