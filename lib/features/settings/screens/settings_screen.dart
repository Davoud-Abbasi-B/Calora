import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/calorie_targets_provider.dart';
import '../widgets/calorie_targets_form.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(calorieTargetsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text('هدف‌های روزانه', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'هدف کالری هر نوع روز را جداگانه تنظیم کنید.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (targets != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CalorieTargetsForm(
                  key: ValueKey(
                    '${targets.trainingDayCalories}-${targets.restDayCalories}',
                  ),
                  initialTargets: targets,
                  buttonLabel: 'ذخیره تغییرات',
                  onSave: (value) async {
                    await ref.read(calorieTargetsProvider.notifier).save(value);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('هدف‌ها ذخیره شدند.')),
                      );
                    }
                  },
                ),
              ),
            ),
          const SizedBox(height: 20),
          Card(
            color: Theme.of(
              context,
            ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'درباره داده‌های غذایی',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'ابتدا پایگاه محلی خوراکی‌های فارسی بررسی می‌شود. در صورت نیاز و در دسترس بودن اینترنت، جست‌وجوی USDA انجام می‌شود. ترجمه نام خوراکی نیز به‌صورت محلی روی دستگاه انجام می‌شود.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
