import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/activation/providers/activation_provider.dart';
import 'features/activation/screens/activation_screen.dart';
import 'features/navigation/main_shell.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/models/calorie_targets.dart';
import 'features/settings/providers/calorie_targets_provider.dart';

enum AppStartDestination { activation, onboarding, main }

const appTitle = 'Calora';

AppStartDestination appStartDestination({
  required bool isActivated,
  required CalorieTargets? targets,
}) {
  if (!isActivated) return AppStartDestination.activation;
  return targets == null
      ? AppStartDestination.onboarding
      : AppStartDestination.main;
}

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
    final activation = ref.watch(activationProvider);
    return switch (appStartDestination(
      isActivated: activation.isActivated,
      targets: targets,
    )) {
      AppStartDestination.activation => const ActivationScreen(),
      AppStartDestination.onboarding => const OnboardingScreen(),
      AppStartDestination.main => const MainShell(),
    };
  }
}
