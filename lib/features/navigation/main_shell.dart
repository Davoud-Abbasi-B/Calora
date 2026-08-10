import 'package:flutter/material.dart';

import '../../core/lifecycle/nutrition_lifecycle_reconciler.dart';
import '../nutrition/screens/history_screen.dart';
import '../nutrition/screens/today_screen.dart';
import '../settings/screens/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => NutritionLifecycleReconciler(
    child: Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [TodayScreen(), HistoryScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'امروز',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'تاریخچه',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'تنظیمات',
          ),
        ],
      ),
    ),
  );
}
