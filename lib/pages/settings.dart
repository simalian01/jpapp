import 'package:flutter/material.dart';
import '../app_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _setBaseDir(BuildContext context) async {
    final m = appModelOf(context);
    final ctl = TextEditingController(text: m.baseDir);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('设置媒体基准目录'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(hintText: '/storage/emulated/0/にほんご'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (res == null || res.isEmpty) return;
    await m.setBaseDir(res);
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('媒体目录：${m.baseDir}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _setBaseDir(context),
                      icon: const Icon(Icons.folder),
                      label: const Text('设置媒体目录'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => m.requestAllFilesAccess(),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('权限'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '专业决策说明：\n'
                  '- 本 App 的核心是“背单词 + 复习间隔”，因此采用 SRS（简化 SM-2）并记录每次自测。\n'
                  '- 内容库与用户进度共用一个 sqlite 文件，但用户表会自动补建，避免导入库不含 user_state/srs 报错。\n'
                  '- 不依赖 FTS5，避免 Android SQLite 不兼容；内容库若包含 FTS 表也不会影响核心功能。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
