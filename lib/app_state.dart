import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';

class PrefKeys {
  static const dbPath = 'content_db_path';
  static const baseDir = 'media_base_dir';
}

/// 全局 App 状态（数据库 + 设置）
class AppModel extends ChangeNotifier {
  Database? _db;
  String? _dbPath;
  String _baseDir = '/storage/emulated/0/にほんご';

  bool _loading = false;
  String? _error;

  Database? get db => _db;
  String? get dbPath => _dbPath;
  String get baseDir => _baseDir;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      _dbPath = sp.getString(PrefKeys.dbPath);
      _baseDir = sp.getString(PrefKeys.baseDir) ?? _baseDir;

      if (_dbPath != null) {
        await openContentDb(_dbPath!);
      }
      _error = null;
    } catch (e) {
      _error = '初始化失败：$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> savePrefs() async {
    final sp = await SharedPreferences.getInstance();
    if (_dbPath != null) {
      await sp.setString(PrefKeys.dbPath, _dbPath!);
    }
    await sp.setString(PrefKeys.baseDir, _baseDir);
  }

  Future<void> requestAllFilesAccess() async {
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return;

    final res = await Permission.manageExternalStorage.request();
    if (!res.isGranted) {
      _error = '未授予“所有文件访问”，图片/音频可能无法读取';
      notifyListeners();
    }
  }

  Future<void> setBaseDir(String dir) async {
    _baseDir = dir.trim();
    await savePrefs();
    notifyListeners();
  }

  /// 导入 sqlite：将外部文件复制到 App 文档目录并打开
  Future<void> importDbFromPath(String srcPath) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await requestAllFilesAccess();
      final src = File(srcPath);
      if (!await src.exists()) throw Exception('文件不存在：$srcPath');

      final docDir = await getApplicationDocumentsDirectory();
      final destPath = '${docDir.path}/jp_study_content.sqlite';
      await src.copy(destPath);

      _dbPath = destPath;
      await savePrefs();
      await openContentDb(destPath);
    } catch (e) {
      _error = '导入失败：$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> openContentDb(String path) async {
    await _db?.close();
    _db = await openDatabase(path, readOnly: false);

    // 关键：确保用户表存在
    await ensureUserTables(_db!);
    final ok = await contentSchemaLooksValid(_db!);
    if (ok) {
    await ensureContentIndexes(_db!); // ✅ 新增：补建内容索引，解决“新词很慢”
    }
    if (!ok) {
      _error = '数据库结构不正确：需要 items/media 表。建议用 scripts/build_db.py 从 Excel 生成。';
    } else {
      _error = null;
    }

    notifyListeners();
  }
}

/// ✅ 用一个具体的 Scope 继承 InheritedNotifier（避免直接 new InheritedNotifier 报 abstract）
class AppScope extends InheritedNotifier<AppModel> {
  const AppScope({
    super.key,
    required AppModel notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static AppModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}

class AppRoot extends StatefulWidget {
  final Widget child;
  const AppRoot({super.key, required this.child});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final model = AppModel();

  @override
  void initState() {
    super.initState();
    model.init();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: model,
      child: widget.child,
    );
  }
}

/// 兼容你其他页面的调用方式
AppModel appModelOf(BuildContext context) => AppScope.of(context);
