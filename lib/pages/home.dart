import 'package:flutter/material.dart';
import '../app_state.dart';
import 'setup.dart';
import 'study.dart';
import 'library.dart';
import 'stats.dart';
import 'settings.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);

    final destinations = [
      (
        icon: Icons.home_outlined,
        label: '初始化',
        builder: const SetupPage(),
      ),
      (
        icon: Icons.school_outlined,
        label: '背单词',
        builder: const StudyPage(),
      ),
      (
        icon: Icons.menu_book_outlined,
        label: '词库',
        builder: const LibraryPage(),
      ),
      (
        icon: Icons.bar_chart_outlined,
        label: '统计',
        builder: const StatsPage(),
      ),
      (
        icon: Icons.settings_outlined,
        label: '设置',
        builder: const SettingsPage(),
      ),
    ];

    return AnimatedBuilder(
      animation: m,
      builder: (_, __) {
        final page = destinations[idx];

        return Scaffold(
          appBar: AppBar(
            title: Text(page.label),
            centerTitle: true,
            scrolledUnderElevation: 0,
          ),
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(key: ValueKey(page.label), child: page.builder),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: idx,
            onDestinationSelected: (i) => setState(() => idx = i),
            destinations: [
              for (final d in destinations)
                NavigationDestination(icon: Icon(d.icon), label: d.label),
            ],
          ),
        );
      },
    );
  }
}
