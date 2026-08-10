import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/persian_date_formatter.dart';
import '../../../core/utils/persian_format.dart';
import '../../settings/models/calorie_targets.dart';
import '../../settings/providers/calorie_targets_provider.dart';
import '../models/daily_nutrition_model.dart';
import '../providers/today_journal_provider.dart';
import '../services/nutrition_journal_service.dart';
import '../widgets/food_entry_section.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal = ref.watch(todayJournalProvider);
    final targets = ref.watch(calorieTargetsProvider);
    final target = journal.report?.targetCalories ?? journal.targetCalories;
    final canReopen =
        journal.report?.submissionType ==
            NutritionReportSubmissionType.manual &&
        journal.report?.dateKey == nutritionDateKey(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('امروز'),
            const SizedBox(height: 2),
            Text(
              formatFullDate(DateTime.now()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (journal.isFinalized) ...[
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'امروز ثبت شده است',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 3),
                              Text('اطلاعات این روز ثبت شده است.'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (canReopen) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _reopenToday(context, ref),
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('ویرایش امروز'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Text('نوع روز', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<NutritionDayType>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: NutritionDayType.training,
                      label: Text('تمرینی'),
                      icon: Icon(Icons.fitness_center, size: 18),
                    ),
                    ButtonSegment(
                      value: NutritionDayType.rest,
                      label: Text('غیرتمرینی'),
                      icon: Icon(Icons.self_improvement, size: 18),
                    ),
                  ],
                  selected: journal.dayType == null
                      ? const {}
                      : {journal.dayType!},
                  emptySelectionAllowed: true,
                  onSelectionChanged: journal.isFinalized
                      ? null
                      : (selection) {
                          if (selection.isNotEmpty && targets != null) {
                            ref
                                .read(todayJournalProvider.notifier)
                                .selectDayType(selection.first, targets);
                          }
                        },
                ),
              ),
            ],
          ),
          if (journal.dayType == null) ...[
            const SizedBox(height: 8),
            Text(
              'برای نمایش هدف امروز، نوع روز را انتخاب کنید.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          _CalorieSummary(totals: journal.totals, target: target),
          const SizedBox(height: 22),
          if (!journal.isFinalized) ...[
            const FoodEntrySection(),
            const SizedBox(height: 24),
          ],
          Text(
            'خوراکی‌های امروز',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (journal.visibleEntries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.restaurant_menu,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'هنوز خوراکی ثبت نشده است.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...journal.visibleEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FoodEntryTile(
                  entry: entry,
                  onDelete: journal.isFinalized
                      ? null
                      : () => ref
                            .read(todayJournalProvider.notifier)
                            .deleteEntry(entry.id),
                ),
              ),
            ),
          if (!journal.isFinalized) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: FilledButton.icon(
                onPressed: () => _finishDay(context, ref, targets),
                icon: const Icon(Icons.task_alt),
                label: const Text('ثبت و پایان روز'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reopenToday(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ویرایش امروز'),
        content: const Text(
          'ثبت امروز باز می‌شود و می‌توانید خوراکی‌ها یا نوع روز را تغییر دهید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ویرایش'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(todayJournalProvider.notifier).reopenToday();
    if (!context.mounted) return;
    switch (result) {
      case ReopenTodayReportResult.reopened:
      case ReopenTodayReportResult.alreadyOpen:
        _message(context, 'امروز برای ویرایش باز شد.');
        return;
      case ReopenTodayReportResult.notToday:
        _message(context, 'فقط گزارش همین روز قابل ویرایش است.');
        return;
      case ReopenTodayReportResult.notManual:
        _message(context, 'فقط ثبت دستی امروز قابل ویرایش است.');
        return;
    }
  }

  Future<void> _finishDay(
    BuildContext context,
    WidgetRef ref,
    CalorieTargets? targets,
  ) async {
    if (targets == null) {
      _message(context, 'ابتدا هدف‌های کالری را در تنظیمات وارد کنید.');
      return;
    }
    final journal = ref.read(todayJournalProvider);
    if (journal.entries.isEmpty) {
      _message(context, 'برای ثبت روز، ابتدا یک خوراکی اضافه کنید.');
      return;
    }
    if (journal.dayType == null) {
      _message(context, 'ابتدا نوع روز را انتخاب کنید.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('روز امروز ثبت شود؟'),
        content: const Text('بعد از ثبت، این روز در تاریخچه ذخیره می‌شود.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ثبت روز'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(todayJournalProvider.notifier).finishDay();
      if (context.mounted) _message(context, 'روز امروز با موفقیت ثبت شد.');
    } on JournalActionException catch (error) {
      if (context.mounted) _message(context, error.message);
    }
  }

  void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _CalorieSummary extends StatelessWidget {
  const _CalorieSummary({required this.totals, required this.target});
  final DailyNutritionTotals totals;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final remaining = target == null ? null : target! - totals.calories;
    final progress = target == null || target == 0
        ? 0.0
        : (totals.calories / target!).clamp(0.0, 1.0);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_fire_department_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  'خلاصه کالری',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _Metric(label: 'هدف امروز', value: target),
                ),
                Expanded(
                  child: _Metric(label: 'مصرف‌شده', value: totals.calories),
                ),
                Expanded(
                  child: _Metric(
                    label: remaining != null && remaining < 0
                        ? 'بیشتر از هدف'
                        : 'باقی‌مانده',
                    value: remaining?.abs(),
                    isWarning: remaining != null && remaining < 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            if (remaining != null && remaining < 0) ...[
              const SizedBox(height: 8),
              Text(
                '${persianNumber(remaining.abs())} کالری بیشتر از هدف',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Divider(
              color: Theme.of(
                context,
              ).colorScheme.onPrimaryContainer.withValues(alpha: 0.18),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _Macro(label: 'پروتئین', value: totals.proteinGrams),
                ),
                Expanded(
                  child: _Macro(label: 'کربوهیدرات', value: totals.carbsGrams),
                ),
                Expanded(
                  child: _Macro(label: 'چربی', value: totals.fatGrams),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, this.value, this.isWarning = false});
  final String label;
  final num? value;
  final bool isWarning;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(
        value == null ? '—' : persianNumber(value!),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: isWarning ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      Text('کالری', style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _Macro extends StatelessWidget {
  const _Macro({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 2),
      Text(
        '${persianNumber(value)} گرم',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _FoodEntryTile extends StatelessWidget {
  const _FoodEntryTile({required this.entry, this.onDelete});
  final DailyNutritionEntry entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.foodName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  entry.quantityText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MacroChip(label: 'پروتئین', value: entry.proteinGrams),
                    _MacroChip(label: 'کربوهیدرات', value: entry.carbsGrams),
                    _MacroChip(label: 'چربی', value: entry.fatGrams),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${persianNumber(entry.calories)} کالری',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(height: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'حذف',
                  onPressed: onDelete,
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.delete_outline, size: 21),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _MacroChip extends StatelessWidget {
  const _MacroChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$label ${persianNumber(value)} گ',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
