import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/navigation/main_shell.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/models/calorie_targets.dart';
import 'features/settings/providers/calorie_targets_provider.dart';

enum AppStartDestination { onboarding, main }

const appTitle = 'Calora';

AppStartDestination appStartDestination(CalorieTargets? targets) =>
    targets == null ? AppStartDestination.onboarding : AppStartDestination.main;

class CalorieTrackerApp extends StatelessWidget {
  const CalorieTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appTitle,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const _DestinationGate(),
    );
  }
}

class _DestinationGate extends ConsumerWidget {
  const _DestinationGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(calorieTargetsProvider);
    return switch (appStartDestination(targets)) {
      AppStartDestination.onboarding => const OnboardingScreen(),
      AppStartDestination.main => const MainShell(),
    };
  }
}
