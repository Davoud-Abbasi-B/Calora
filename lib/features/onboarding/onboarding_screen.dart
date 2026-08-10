import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/providers/calorie_targets_provider.dart';
import '../settings/widgets/calorie_targets_form.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'نشان Calora',
                  image: true,
                  child: SizedBox(
                    height: 150,
                    child: Image.asset(
                      'assets/logo/app_logo.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'هدف کالری روزانه',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'برای محاسبه کالری باقی‌مانده، هدف روزهای تمرینی و غیرتمرینی را وارد کنید.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                CalorieTargetsForm(
                  buttonLabel: 'شروع',
                  onSave: ref.read(calorieTargetsProvider.notifier).save,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
