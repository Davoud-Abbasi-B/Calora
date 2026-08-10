import 'package:flutter/material.dart';

import '../../../core/utils/persian_date_formatter.dart';
import '../../../core/utils/persian_format.dart';
import '../models/daily_nutrition_model.dart';
import 'history_screen.dart';

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({required this.report, super.key});
  final DailyNutritionReport report;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('جزئیات روز')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          formatDateKey(report.dateKey),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${nutritionDayTypeLabel(report.dayType)} • '
          '${submissionTypeLabel(report.submissionType)}',
        ),
        const SizedBox(height: 24),
        _ReportTotals(report: report),
        const SizedBox(height: 28),
        Text('خوراکی‌ها', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        ...report.entries.map(
          (entry) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.foodName),
            subtitle: Text(
              '${entry.quantityText} • پروتئین ${persianNumber(entry.proteinGrams)}، '
              'کربوهیدرات ${persianNumber(entry.carbsGrams)}، '
              'چربی ${persianNumber(entry.fatGrams)} گرم',
            ),
            trailing: Text('${persianNumber(entry.calories)} کالری'),
          ),
        ),
      ],
    ),
  );
}

class _ReportTotals extends StatelessWidget {
  const _ReportTotals({required this.report});
  final DailyNutritionReport report;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            report.targetCalories == null
                ? '${persianNumber(report.totalCalories)} کالری'
                : '${persianNumber(report.totalCalories)} از '
                      '${persianNumber(report.targetCalories!)} کالری',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text('پروتئین: ${persianNumber(report.totalProteinGrams)} گرم'),
          Text('کربوهیدرات: ${persianNumber(report.totalCarbsGrams)} گرم'),
          Text('چربی: ${persianNumber(report.totalFatGrams)} گرم'),
        ],
      ),
    ),
  );
}
