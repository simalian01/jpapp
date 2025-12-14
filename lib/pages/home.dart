import 'package:flutter/material.dart';
import '../app_state.dart';
import 'setup.dart';
import 'study.dart';
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

    final pages = [
      const SetupPage(),
      const StudyPage(),
      const StatsPage(),
      const SettingsPage(),
    ];

    return AnimatedBuilder(
      animation: m,
      builder: (_, __) {
        return Scaffold(
          body: SafeArea(child: pages[idx]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: idx,
            onDestinationSelected: (i) => setState(() => idx = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: '初始化'),
              NavigationDestination(icon: Icon(Icons.school), label: '背单词'),
              NavigationDestination(icon: Icon(Icons.bar_chart), label: '统计'),
              NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        );
      },
    );
  }
}
