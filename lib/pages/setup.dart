import 'dart:io';
import 'package:flutter/material.dart';
import '../app_state.dart';
import 'package:file_picker/file_picker.dart';

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  Future<void> _importViaPicker(BuildContext context) async {
    final m = appModelOf(context);
    await m.requestAllFilesAccess();

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
        const Text('初始化（开箱即用）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('内置词库：${m.dbPath ?? "未就绪"}'),
                const SizedBox(height: 6),
                Text('媒体基准目录：${m.baseDir}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: m.loading
                          ? null
                          : () async {
                              await m.init();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已重新校验并准备好内置词库')),
                                );
                              }
                            },
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('重新准备内置词库'),
                    ),
                    OutlinedButton.icon(
                      onPressed: m.loading ? null : () => _importViaPicker(context),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('（可选）用外部库替换'),
                    ),
                    OutlinedButton.icon(
                      onPressed: m.loading ? null : () => m.requestAllFilesAccess(),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('申请所有文件访问'),
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
                  '说明：应用已内置完整数据库，安装后即可用。媒体文件请放在 /storage/emulated/0/にほんご 下，'
                  '自动按照表内路径拼接，例如 《B词汇·红宝书》/、《A 新日本语教程》/初级1 等子目录。'
                  '如需自定义词库，可选择外部 sqlite 文件覆盖。',
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
