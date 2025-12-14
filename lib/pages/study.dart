import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../db.dart';

enum StudyMode { mixed, newOnly, dueOnly }

extension StudyModeLabel on StudyMode {
  String get label {
    switch (this) {
      case StudyMode.mixed:
        return '到期复习 + 新词（推荐）';
      case StudyMode.newOnly:
        return '只学新词';
      case StudyMode.dueOnly:
        return '只复习到期';
    }
  }
}

enum Rating { again, hard, good, easy }

extension RatingLabel on Rating {
  String get label {
    switch (this) {
      case Rating.again:
        return 'Again';
      case Rating.hard:
        return 'Hard';
      case Rating.good:
        return 'Good';
      case Rating.easy:
        return 'Easy';
    }
  }
}

/// 背单词入口页
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  Database? _lastDb;

  List<String> decks = [];
  List<String> levels = ['全部'];

  String deck = '';
  String level = '全部';
  StudyMode mode = StudyMode.mixed;
  int count = 20;

  bool loadingMeta = false;
  String? metaErr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = appModelOf(context);
    final db = m.db;
    if (db == null) return;
    if (!identical(db, _lastDb)) {
      _lastDb = db;
      _loadMeta(db);
    }
  }

  Future<void> _loadMeta(Database db) async {
    setState(() {
      loadingMeta = true;
      metaErr = null;
    });

    try {
      // 只把“有 N1~N5 level 的 deck”当作可背单词的词库
      final deckRows = await db.rawQuery("""
        SELECT DISTINCT deck
        FROM items
        WHERE level LIKE 'N%'
        ORDER BY deck;
      """);

      decks = deckRows.map((e) => (e['deck'] as String).trim()).where((s) => s.isNotEmpty).toList();
      if (decks.isEmpty) {
        throw Exception('数据库里没有找到可背单词的词库（需要 level=N1~N5）');
      }

      // 默认优先红宝书
      deck = decks.contains('红宝书') ? '红宝书' : decks.first;

      await _loadLevels(db, deck);

      if (!levels.contains(level)) level = '全部';
    } catch (e) {
      metaErr = '$e';
    } finally {
      if (mounted) {
        setState(() => loadingMeta = false);
      }
    }
  }

  Future<void> _loadLevels(Database db, String deck) async {
    final rows = await db.rawQuery("""
      SELECT DISTINCT level
      FROM items
      WHERE deck=? AND level LIKE 'N%'
      ORDER BY level DESC;
    """, [deck]);

    final lv = rows.map((e) => (e['level'] as String).trim()).where((s) => s.isNotEmpty).toList();
    levels = ['全部', ...lv.reversed]; // N5..N1
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);
    final ready = m.db != null && m.error == null;

    return Scaffold(
      appBar: AppBar(title: const Text('背单词')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: !ready
            ? const Text('请先在【初始化】导入词库（jp_study_content.sqlite）')
            : loadingMeta
                ? const Center(child: CircularProgressIndicator())
                : metaErr != null
                    ? Text('加载词库信息失败：$metaErr')
                    : Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('词库：${m.dbPath ?? ""}', style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: deck,
                                      decoration: const InputDecoration(labelText: '词库/书'),
                                      items: decks.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                                      onChanged: (v) async {
                                        if (v == null) return;
                                        setState(() => deck = v);
                                        await _loadLevels(m.db!, deck);
                                        if (!levels.contains(level)) setState(() => level = '全部');
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: level,
                                      decoration: const InputDecoration(labelText: '等级（可不选）'),
                                      items: levels.map((lv) => DropdownMenuItem(value: lv, child: Text(lv))).toList(),
                                      onChanged: (v) => setState(() => level = v ?? '全部'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<StudyMode>(
                                value: mode,
                                decoration: const InputDecoration(labelText: '模式'),
                                items: StudyMode.values
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                                    .toList(),
                                onChanged: (v) => setState(() => mode = v ?? mode),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<int>(
                                value: count,
                                decoration: const InputDecoration(labelText: '数量'),
                                items: const [10, 20, 30, 40, 60, 80]
                                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                                    .toList(),
                                onChanged: (v) => setState(() => count = v ?? 20),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('开始自测'),
                                  onPressed: () async {
                                    final db = m.db!;
                                    final baseDir = m.baseDir;

                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StudySessionPage(
                                          db: db,
                                          baseDir: baseDir,
                                          deck: deck,
                                          level: level,
                                          mode: mode,
                                          targetCount: count,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '评分含义：Again=忘记（很快再出现）｜Hard=困难｜Good=记住｜Easy=秒懂（间隔更长）',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
      ),
    );
  }
}

/// ✅ 会话页（彻底避免“转圈圈无限加载”）
/// - db/baseDir 由构造函数传入
/// - initState 只 load 一次
class StudySessionPage extends StatefulWidget {
  final Database db;
  final String baseDir;

  final String deck;
  final String level; // '全部' or N1..N5
  final StudyMode mode;
  final int targetCount;

  const StudySessionPage({
    super.key,
    required this.db,
    required this.baseDir,
    required this.deck,
    required this.level,
    required this.mode,
    required this.targetCount,
  });

  @override
  State<StudySessionPage> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends State<StudySessionPage> {
  bool loading = true;
  String? err;

  List<int> ids = [];
  int idx = 0;

  Map<String, Object?>? item;
  Map<String, Object?>? srs;
  String? audioPath;
  String? imagePath;
  bool audioExists = false;
  bool imageExists = false;

  bool showAnswer = false;

  final player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSession());
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String _resolveMediaPath(String raw) {
    final p = raw.replaceAll('\\', '/');
    const marker = '/にほんご/';
    final i = p.indexOf(marker);
    if (i >= 0) {
      final rel = p.substring(i + marker.length);
      return '${widget.baseDir}/$rel';
    }
    final p2 = p.replaceFirst(RegExp(r'^[A-Za-z]:/'), '');
    return '${widget.baseDir}/${p2.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Future<void> _loadSession() async {
    setState(() {
      loading = true;
      err = null;
    });

    try {
      final picked = await _pickIds(
        db: widget.db,
        deck: widget.deck,
        level: widget.level,
        mode: widget.mode,
        targetCount: widget.targetCount,
      );

      if (picked.isEmpty) {
        throw Exception('没有抽到任何单词（可能该等级没有数据，或该模式下无可用项）');
      }

      ids = picked;
      idx = 0;

      await _loadCurrent();
    } catch (e) {
      err = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<int>> _pickIds({
    required Database db,
    required String deck,
    required String level,
    required StudyMode mode,
    required int targetCount,
  }) async {
    final today = epochDay(DateTime.now());
    final where = <String>['i.deck=?', "i.level LIKE 'N%'"];
    final args = <Object?>[deck];

    if (level != '全部') {
      where.add('i.level=?');
      args.add(level);
    }

    // 为了速度：不使用 ORDER BY RANDOM() 直接全表随机
    // 先取一大段候选（比如 targetCount*4），再在 Dart 里 shuffle
    final int candidate = max(targetCount * 4, targetCount);

    Future<List<int>> queryNew() async {
      final rows = await db.rawQuery("""
        SELECT i.id AS id
        FROM items i
        LEFT JOIN srs s ON s.item_id=i.id
        WHERE ${where.join(' AND ')} AND s.item_id IS NULL
        ORDER BY i.id DESC
        LIMIT ?;
      """, [...args, candidate]);
      return rows.map((e) => (e['id'] as int)).toList();
    }

    Future<List<int>> queryDue() async {
      final rows = await db.rawQuery("""
        SELECT i.id AS id
        FROM items i
        JOIN srs s ON s.item_id=i.id
        WHERE ${where.join(' AND ')} AND s.due_day <= ?
        ORDER BY s.due_day ASC, i.id DESC
        LIMIT ?;
      """, [...args, today, candidate]);
      return rows.map((e) => (e['id'] as int)).toList();
    }

    List<int> pool = [];
    if (mode == StudyMode.newOnly) {
      pool = await queryNew();
    } else if (mode == StudyMode.dueOnly) {
      pool = await queryDue();
    } else {
      final due = await queryDue();
      final nw = await queryNew();
      pool = [...due, ...nw];
    }

    pool = pool.toSet().toList(); // 去重
    pool.shuffle(Random(DateTime.now().millisecondsSinceEpoch));

    if (pool.length > targetCount) pool = pool.take(targetCount).toList();
    return pool;
  }

  Future<void> _loadCurrent() async {
    setState(() {
      loading = true;
      err = null;
      showAnswer = false;
    });

    try {
      final id = ids[idx];

      final it = await widget.db.query('items', where: 'id=?', whereArgs: [id], limit: 1);
      if (it.isEmpty) throw Exception('找不到单词 id=$id');
      item = it.first;

      final sr = await widget.db.query('srs', where: 'item_id=?', whereArgs: [id], limit: 1);
      srs = sr.isEmpty ? null : sr.first;

      final md = await widget.db.query('media', where: 'item_id=?', whereArgs: [id]);
      final a = md.where((e) => e['type'] == 'audio').toList();
      final img = md.where((e) => e['type'] == 'image').toList();

      audioPath = a.isEmpty ? null : _resolveMediaPath((a.first['path'] as String).trim());
      imagePath = img.isEmpty ? null : _resolveMediaPath((img.first['path'] as String).trim());

      audioExists = audioPath != null && File(audioPath!).existsSync();
      imageExists = imagePath != null && File(imagePath!).existsSync();
    } catch (e) {
      err = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _play() async {
    if (!audioExists || audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('音频不存在：${audioPath ?? "(空)"}')),
      );
      return;
    }
    await player.setFilePath(audioPath!);
    await player.play();
  }

  Future<void> _rate(Rating r) async {
    final it = item;
    if (it == null) return;
    final id = (it['id'] as num).toInt();

    final today = epochDay(DateTime.now());

    // 读现有 srs
    double ease = (srs?['ease'] as num?)?.toDouble() ?? 2.5;
    int reps = (srs?['reps'] as num?)?.toInt() ?? 0;
    int interval = (srs?['interval_days'] as num?)?.toInt() ?? 0;

    // 简化 SM-2（足够成熟、稳定）
    switch (r) {
      case Rating.again:
        ease = max(1.3, ease - 0.2);
        reps = 0;
        interval = 1;
        break;
      case Rating.hard:
        ease = max(1.3, ease - 0.05);
        reps += 1;
        interval = max(1, (interval == 0 ? 1 : (interval * 1.2).round()));
        break;
      case Rating.good:
        reps += 1;
        interval = max(1, (interval == 0 ? 1 : (interval * ease).round()));
        break;
      case Rating.easy:
        ease = min(3.0, ease + 0.05);
        reps += 1;
        interval = max(2, (interval == 0 ? 2 : (interval * ease * 1.3).round()));
        break;
    }

    final due = today + interval;

    await widget.db.transaction((txn) async {
      await txn.execute("""
        INSERT INTO srs(item_id, reps, interval_days, due_day, ease, last_day)
        VALUES(?,?,?,?,?,?)
        ON CONFLICT(item_id) DO UPDATE SET
          reps=excluded.reps,
          interval_days=excluded.interval_days,
          due_day=excluded.due_day,
          ease=excluded.ease,
          last_day=excluded.last_day;
      """, [id, reps, interval, due, ease, today]);

      await txn.execute("""
        INSERT INTO reviews(day, item_id, rating)
        VALUES(?,?,?);
      """, [today, id, r.label]);
    });

    // 下一题
    if (idx + 1 >= ids.length) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    setState(() => idx += 1);
    await _loadCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final it = item;

    return Scaffold(
      appBar: AppBar(
        title: Text('自测 ${min(idx + 1, ids.length)}/${ids.length}'),
        actions: [
          IconButton(
            tooltip: showAnswer ? '隐藏答案' : '显示答案',
            onPressed: () => setState(() => showAnswer = !showAnswer),
            icon: Icon(showAnswer ? Icons.visibility_off : Icons.visibility),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(child: Text('加载失败：$err'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (it?['term'] as String?) ?? '',
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text('かな：${(it?['reading'] as String?) ?? ''}'),
                            Text('等级：${(it?['level'] as String?) ?? ''}'),
                            const SizedBox(height: 10),
                            if (!showAnswer)
                              const Text('点击右上角 👁 显示答案/释义（如果词库有）', style: TextStyle(fontSize: 12))
                            else
                              Text('释义：${(it?['meaning'] as String?) ?? ''}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _play,
                          icon: const Icon(Icons.volume_up),
                          label: Text(audioExists ? '播放音频' : '音频缺失'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (!imageExists || imagePath == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('图片不存在：${imagePath ?? "(空)"}')),
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => _ImageViewer(path: imagePath!)),
                            );
                          },
                          icon: const Icon(Icons.image),
                          label: Text(imageExists ? '查看图片' : '图片缺失'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (imageExists && imagePath != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(imagePath!), fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text('评分', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(onPressed: () => _rate(Rating.again), child: const Text('Again')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(onPressed: () => _rate(Rating.hard), child: const Text('Hard')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(onPressed: () => _rate(Rating.good), child: const Text('Good')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(onPressed: () => _rate(Rating.easy), child: const Text('Easy')),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String path;
  const _ImageViewer({required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('图片')),
      body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
    );
  }
}
