import 'package:flutter/material.dart';
import '../app_state.dart';
import 'package:file_picker/file_picker.dart';

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  Future<void> _importViaPicker(BuildContext context) async {
    final m = appModelOf(context);
    await m.requestAllFilesAccess();

    // 有些系统不弹，这里仍提供。推荐用“自动从 Download 导入”
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite', 'db'],
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.path != null) {
      await m.importDbFromPath(f.path!);
    }
  }

  Future<void> _importAutoFromDownload(BuildContext context) async {
    final m = appModelOf(context);
    await m.requestAllFilesAccess();

    const candidates = [
      '/storage/emulated/0/Download/jp_study_content.sqlite',
      '/storage/emulated/0/Downloads/jp_study_content.sqlite',
      '/sdcard/Download/jp_study_content.sqlite',
      '/sdcard/Downloads/jp_study_content.sqlite',
    ];
    for (final p in candidates) {
      final ok = await File(p).exists();
      if (ok) {
        await m.importDbFromPath(p);
        return;
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未在 Download 找到 jp_study_content.sqlite，请确认文件名/位置')),
      );
    }
  }

  Future<void> _setBaseDir(BuildContext context) async {
    final m = appModelOf(context);
    final ctl = TextEditingController(text: m.baseDir);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('设置媒体基准目录'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
            hintText: '/storage/emulated/0/にほんご',
          ),
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
        const Text('初始化（第一次必做）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('词库：${m.dbPath ?? "未导入"}'),
                const SizedBox(height: 6),
                Text('媒体基准目录：${m.baseDir}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: m.loading ? null : () => _importAutoFromDownload(context),
                      icon: const Icon(Icons.download),
                      label: const Text('自动从 Download 导入词库'),
                    ),
                    OutlinedButton.icon(
                      onPressed: m.loading ? null : () => _importViaPicker(context),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('选择文件导入（可选）'),
                    ),
                    OutlinedButton.icon(
                      onPressed: m.loading ? null : () => m.requestAllFilesAccess(),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('申请“所有文件访问”'),
                    ),
                    OutlinedButton.icon(
                      onPressed: m.loading ? null : () => _setBaseDir(context),
                      icon: const Icon(Icons.folder),
                      label: const Text('设置媒体目录'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '建议：\n'
                  '1) 把媒体库放到 /storage/emulated/0/にほんご\n'
                  '2) 把词库放到 Download 并命名为 jp_study_content.sqlite\n'
                  '3) 词库推荐用 scripts/build_db.py 从 Excel 生成，避免 FTS5 不兼容',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (m.loading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (m.error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(m.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
      ],
    );
  }
}
