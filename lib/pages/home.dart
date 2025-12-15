import 'package:flutter/material.dart';
import '../app_state.dart';
import 'study.dart';
import 'library.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  Future<void> _maybeShowOnboarding() async {
    final m = appModelOf(context);
    if (m.onboarded) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('首次使用须知', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('媒体资源默认放在 /storage/emulated/0/にほんご 目录下。应用只在首次启动时请求一次文件权限，用于读取音频/图片。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('已了解，授权读取媒体'),
              onPressed: () async {
                await m.requestAllFilesAccess();
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后再说（仍可使用，无重复弹窗）'),
            ),
          ],
        ),
      ),
    );

    await m.markOnboarded();
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);

    final destinations = [
      (
        icon: Icons.quiz_outlined,
        label: '自测',
        builder: const StudyPage(),
      ),
      (
        icon: Icons.memory_outlined,
        label: '记忆',
        builder: const LibraryPage(),
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
