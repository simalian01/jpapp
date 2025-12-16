import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';

class PrefKeys {
  static const dbPath = 'content_db_path';
  static const baseDir = 'media_base_dir';
  static const onboarded = 'onboarded_once';
}

/// 全局 App 状态（数据库 + 设置）
class AppModel extends ChangeNotifier {
  Database? _db;
  String? _dbPath;
  String _baseDir = '/storage/emulated/0/にほんご';
  bool _onboarded = false;
  bool _loggingUsage = false;

  bool _loading = false;
  String? _error;

  Database? get db => _db;
  String? get dbPath => _dbPath;
  String get baseDir => _baseDir;
  bool get loading => _loading;
  String? get error => _error;
  bool get onboarded => _onboarded;

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      _dbPath = sp.getString(PrefKeys.dbPath);
      _baseDir = sp.getString(PrefKeys.baseDir) ?? _baseDir;
      _onboarded = sp.getBool(PrefKeys.onboarded) ?? false;

      await _prepareBundledDbIfNeeded();

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
    await sp.setBool(PrefKeys.onboarded, _onboarded);
  }

  /// 将内置词库拷贝到应用沙盒，避免手工导入
  Future<void> _prepareBundledDbIfNeeded() async {
    if (_dbPath != null && await File(_dbPath!).exists()) return;

    final docDir = await getApplicationDocumentsDirectory();
    final destPath = '${docDir.path}/jp_study_content.sqlite';
    final dest = File(destPath);

    if (!await dest.exists()) {
      final data = await rootBundle.load('assets/jp_study_content.sqlite');
      await dest.writeAsBytes(data.buffer.asUint8List());
    }

    _dbPath = destPath;
    await savePrefs();
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

  Future<void> logUsage({int seconds = 0, int detailOpens = 0, int remembered = 0, int forgotten = 0}) async {
    final db = _db;
    if (db == null || (seconds == 0 && detailOpens == 0 && remembered == 0 && forgotten == 0)) return;

    // 避免同时被多个入口重入
    if (_loggingUsage) return;
    _loggingUsage = true;
    try {
      final day = epochDay(DateTime.now());
      await db.insert(
        'usage_stats',
        {'day': day},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await db.rawUpdate(
        'UPDATE usage_stats SET seconds=seconds+?, detail_opens=detail_opens+?, remembered=remembered+?, forgotten=forgotten+? WHERE day=?',
        [seconds, detailOpens, remembered, forgotten, day],
      );
    } finally {
      _loggingUsage = false;
    }
  }

  Future<void> markOnboarded() async {
    _onboarded = true;
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
    if (scope == null) {
      throw FlutterError('AppScope not found. 请确认 AppRoot 包裹在 MaterialApp 之上');
    }
    return scope.notifier!;
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
