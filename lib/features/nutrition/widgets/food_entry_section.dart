import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/persian_format.dart';
import '../models/food_analysis_result.dart';
import '../providers/food_analysis_provider.dart';
import '../providers/nutrition_providers.dart';
import '../providers/today_journal_provider.dart';
import '../services/food_analysis_service.dart';
import '../services/local_food_database_service.dart';
import '../services/persian_food_parser.dart';

class FoodEntrySection extends ConsumerStatefulWidget {
  const FoodEntrySection({super.key});

  @override
  ConsumerState<FoodEntrySection> createState() => _FoodEntrySectionState();
}

class _FoodEntrySectionState extends ConsumerState<FoodEntrySection> {
  final _controller = TextEditingController();
  bool _isRegistering = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = ref.watch(foodAnalysisStateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('افزودن خوراکی', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          enabled: !analysis.isLoading,
          textAlign: TextAlign.start,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _analyze(),
          decoration: const InputDecoration(
            hintText: 'مثلاً ۲ عدد تخم‌مرغ یا ۱۰۰ گرم برنج',
            prefixIcon: Icon(Icons.restaurant_outlined),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: analysis.isLoading ? null : _analyze,
          icon: analysis.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.calculate_outlined),
          label: Text(analysis.isLoading ? 'در حال محاسبه...' : 'محاسبه'),
        ),
        if (analysis.message != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              analysis.message!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
        if (analysis.batch != null) ...[
          const SizedBox(height: 16),
          _AnalysisPreview(
            batch: analysis.batch!,
            isRegistering: _isRegistering,
            onRegister: _register,
            onManual: _manualEntry,
            onPortion: _portionEntry,
            onCandidates: _chooseCandidate,
            onTranslation: _correctTranslation,
            onCancel: () =>
                ref.read(foodAnalysisStateProvider.notifier).clear(),
          ),
        ],
      ],
    );
  }

  void _analyze() =>
      ref.read(foodAnalysisStateProvider.notifier).analyze(_controller.text);

  Future<void> _register() async {
    if (_isRegistering) return;
    final batch = ref.read(foodAnalysisStateProvider).batch;
    if (batch == null || !batch.canConfirm) return;
    setState(() => _isRegistering = true);
    try {
      await ref
          .read(todayJournalProvider.notifier)
          .addAnalysisItems(batch.items);
      ref.read(foodAnalysisStateProvider.notifier).clear();
      _controller.clear();
      if (mounted) _message('خوراکی‌ها به امروز اضافه شدند.');
    } catch (_) {
      if (mounted) _message('ثبت خوراکی‌ها ممکن نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  Future<void> _chooseCandidate(UnresolvedFoodItem item) async {
    final candidate = await showDialog<FoodAnalysisCandidate>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('انتخاب نتیجه برای «${item.foodName}»'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: item.candidates.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final candidate = item.candidates[index];
              return ListTile(
                title: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(candidate.description),
                ),
                subtitle: Text(
                  '${persianNumber(candidate.caloriesPer100g)} کالری در ۱۰۰ گرم',
                ),
                onTap: () => Navigator.pop(context, candidate),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
        ],
      ),
    );
    if (candidate == null || !mounted) return;
    await _guarded(
      () => ref
          .read(foodAnalysisStateProvider.notifier)
          .resolveCandidate(item, candidate),
    );
  }

  Future<void> _portionEntry(UnresolvedFoodItem item) async {
    final controller = TextEditingController();
    final grams = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('وزن تقریبی هر عدد'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'وزن هر عدد',
            suffixText: 'گرم',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () {
              final value = _number(controller.text);
              if (value != null && value > 0) Navigator.pop(context, value);
            },
            child: const Text('محاسبه'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (grams == null || !mounted) return;
    await _guarded(
      () => ref
          .read(foodAnalysisStateProvider.notifier)
          .resolvePortion(item, grams),
    );
  }

  Future<void> _correctTranslation(UnresolvedFoodItem item) async {
    final controller = TextEditingController(text: item.searchPhrase ?? '');
    var save = true;
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('اصلاح عبارت انگلیسی'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'عبارت انگلیسی برای USDA',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: save,
                onChanged: (value) =>
                    setDialogState(() => save = value ?? false),
                title: const Text('ذخیره برای دفعات بعد'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                final phrase = controller.text.trim();
                if (phrase.isNotEmpty) Navigator.pop(context, (phrase, save));
              },
              child: const Text('جست‌وجوی دوباره'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _guarded(
      () => ref
          .read(foodAnalysisStateProvider.notifier)
          .retryWithTranslation(item, result.$1, saveForLater: result.$2),
    );
  }

  Future<void> _manualEntry(UnresolvedFoodItem item) async {
    final name = TextEditingController(text: item.foodName);
    final calories = TextEditingController();
    final protein = TextEditingController();
    final carbs = TextEditingController();
    final fat = TextEditingController();
    var saveCustom = false;
    final result = await showDialog<FoodAnalysisResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ورود دستی خوراکی'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('مقادیر را برای همین مقدار مصرف‌شده وارد کنید.'),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'نام خوراکی'),
                ),
                const SizedBox(height: 8),
                _NumberField(controller: calories, label: 'کالری'),
                _NumberField(controller: protein, label: 'پروتئین'),
                _NumberField(controller: carbs, label: 'کربوهیدرات'),
                _NumberField(controller: fat, label: 'چربی'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: saveCustom,
                  onChanged: (value) =>
                      setDialogState(() => saveCustom = value ?? false),
                  title: const Text('ذخیره در خوراکی‌های من'),
                  subtitle: const Text(
                    'برای مقادیر گرم و کیلوگرم قابل ذخیره است.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () async {
                final values = [
                  calories,
                  protein,
                  carbs,
                  fat,
                ].map((controller) => _number(controller.text)).toList();
                if (name.text.trim().isEmpty ||
                    !validManualNutritionValues(values)) {
                  return;
                }
                final grams = _consumedGrams(item);
                if (saveCustom && grams != null && grams > 0) {
                  final multiplier = 100 / grams;
                  await ref
                      .read(localStorageServiceProvider)
                      .saveCustomFood(
                        LocalFoodDefinition(
                          id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
                          nameFa: name.text.trim(),
                          aliasesFa: const [],
                          searchTermsEn: const [],
                          basisAmount: 100,
                          calories: values[0]! * multiplier,
                          proteinGrams: values[1]! * multiplier,
                          carbsGrams: values[2]! * multiplier,
                          fatGrams: values[3]! * multiplier,
                          source: 'user_custom',
                          defaultGramConversions: const {},
                          isCustom: true,
                        ),
                      );
                  ref.read(localFoodDatabaseProvider).invalidateCustomFoods();
                }
                if (!context.mounted) return;
                Navigator.pop(
                  context,
                  FoodAnalysisResult(
                    originalInput: item.originalSegment,
                    foodName: name.text.trim(),
                    quantityText: item.quantityText,
                    calories: values[0]!,
                    proteinGrams: values[1]!,
                    carbsGrams: values[2]!,
                    fatGrams: values[3]!,
                    consumedGrams: grams,
                    isEstimated: true,
                    confidence: 'high',
                    assumptions: const ['مقادیر توسط کاربر وارد شده‌اند.'],
                    sourceType: FoodSourceType.manual,
                    sourceLabel: 'ورود دستی',
                  ),
                );
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    calories.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
    if (result != null && mounted) {
      ref.read(foodAnalysisStateProvider.notifier).replace(item, [result]);
    }
  }

  double? _consumedGrams(UnresolvedFoodItem item) {
    if (item.consumedGrams != null) return item.consumedGrams;
    if (item.quantity == null) return null;
    if (item.unit == FoodUnit.gram.name) return item.quantity;
    if (item.unit == FoodUnit.kilogram.name) return item.quantity! * 1000;
    return null;
  }

  double? _number(String value) =>
      double.tryParse(normalizePersianText(value).replaceAll('٫', '.'));

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) _message('انجام این عملیات ممکن نشد. دوباره تلاش کنید.');
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _AnalysisPreview extends StatelessWidget {
  const _AnalysisPreview({
    required this.batch,
    required this.isRegistering,
    required this.onRegister,
    required this.onManual,
    required this.onPortion,
    required this.onCandidates,
    required this.onTranslation,
    required this.onCancel,
  });

  final FoodAnalysisBatchResult batch;
  final bool isRegistering;
  final VoidCallback onRegister;
  final Future<void> Function(UnresolvedFoodItem) onManual;
  final Future<void> Function(UnresolvedFoodItem) onPortion;
  final Future<void> Function(UnresolvedFoodItem) onCandidates;
  final Future<void> Function(UnresolvedFoodItem) onTranslation;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'پیش‌نمایش محاسبه',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...batch.items.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.foodName} • ${item.quantityText}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${persianNumber(item.calories)} کالری | '
                    'پروتئین ${persianNumber(item.proteinGrams)} | '
                    'کربوهیدرات ${persianNumber(item.carbsGrams)} | '
                    'چربی ${persianNumber(item.fatGrams)} گرم',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  ...item.assumptions.map((text) => Text('• $text')),
                  ...item.warnings.map(
                    (text) => Text(
                      'هشدار: $text',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...batch.unresolvedItems.map(
            (item) => _UnresolvedFoodCard(
              item: item,
              onManual: () => onManual(item),
              onPortion: () => onPortion(item),
              onCandidates: () => onCandidates(item),
              onTranslation: () => onTranslation(item),
            ),
          ),
          if (batch.items.isNotEmpty) ...[
            const SizedBox(height: 2),
            const Divider(),
            Text(
              'جمع: ${persianNumber(batch.totals.calories)} کالری',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
          if (!batch.canConfirm) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'برای فعال شدن ثبت، ابتدا موارد پیدانشده را تکمیل کنید.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: batch.canConfirm && !isRegistering ? onRegister : null,
            child: Text(isRegistering ? 'در حال ثبت...' : 'ثبت'),
          ),
          TextButton(onPressed: onCancel, child: const Text('لغو')),
        ],
      ),
    ),
  );
}

class _UnresolvedFoodCard extends StatelessWidget {
  const _UnresolvedFoodCard({
    required this.item,
    required this.onManual,
    required this.onPortion,
    required this.onCandidates,
    required this.onTranslation,
  });

  final UnresolvedFoodItem item;
  final VoidCallback onManual;
  final VoidCallback onPortion;
  final VoidCallback onCandidates;
  final VoidCallback onTranslation;

  @override
  Widget build(BuildContext context) {
    final canCorrectPhrase =
        item.searchPhrase != null ||
        item.status == FoodResolutionStatus.translationUnavailable;
    final needsPortion =
        item.status == FoodResolutionStatus.needsPortion &&
        item.unit == FoodUnit.item.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.search_off_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.foodName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text('این خوراکی در پایگاه داده پیدا نشد.'),
                    if (item.reason.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.reason,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.edit_note),
            label: const Text('ورود دستی'),
          ),
          if (canCorrectPhrase) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onTranslation,
              icon: const Icon(Icons.find_replace),
              label: const Text('اصلاح عبارت'),
            ),
          ],
          if (item.candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onCandidates,
              child: const Text('انتخاب نتیجه نزدیک'),
            ),
          ],
          if (needsPortion) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onPortion,
              child: const Text('وزن تقریبی هر عدد'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    ),
  );
}
