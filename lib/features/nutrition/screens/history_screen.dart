import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/persian_date_formatter.dart';
import '../../../core/utils/persian_format.dart';
import '../models/daily_nutrition_model.dart';
import '../providers/today_journal_provider.dart';
import 'report_detail_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تاریخچه')),
      body: reports.isEmpty
          ? const Center(child: Text('هنوز روزی ثبت نشده است.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final report = reports[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      formatDateKey(report.dateKey),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${_dayTypeLabel(report.dayType)} • '
                        '${_submissionLabel(report.submissionType)}',
                      ),
                    ),
                    trailing: Text(
                      report.targetCalories == null
                          ? '${persianNumber(report.totalCalories)} کالری'
                          : '${persianNumber(report.totalCalories)} / '
                                '${persianNumber(report.targetCalories!)} کالری',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReportDetailScreen(report: report),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String nutritionDayTypeLabel(NutritionDayType value) => _dayTypeLabel(value);
String submissionTypeLabel(NutritionReportSubmissionType value) =>
    _submissionLabel(value);

String _dayTypeLabel(NutritionDayType value) => switch (value) {
  NutritionDayType.training => 'تمرینی',
  NutritionDayType.rest => 'غیرتمرینی',
};

String _submissionLabel(NutritionReportSubmissionType value) => switch (value) {
  NutritionReportSubmissionType.manual => 'ثبت دستی',
  NutritionReportSubmissionType.automatic => 'ثبت خودکار',
};
