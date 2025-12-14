import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../db.dart';
import '../models.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  String deck = '红宝书';
  String level = 'N5';
  StudyMode mode = StudyMode.due;
  int count = 20;

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);
    final ready = m.db != null && m.error == null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('背单词', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('词库：${m.dbPath ?? "未导入"}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: deck,
                        decoration: const InputDecoration(labelText: '词库/书'),
                        items: const [
                          DropdownMenuItem(value: '红宝书', child: Text('红宝书')),
                        ],
                        onChanged: (v) => setState(() => deck = v ?? deck),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: level,
                        decoration: const InputDecoration(labelText: '等级'),
                        items: const [
                          DropdownMenuItem(value: 'N5', child: Text('N5')),
                          DropdownMenuItem(value: 'N4', child: Text('N4')),
                          DropdownMenuItem(value: 'N3', child: Text('N3')),
                          DropdownMenuItem(value: 'N2', child: Text('N2')),
                          DropdownMenuItem(value: 'N1', child: Text('N1')),
                        ],
                        onChanged: (v) => setState(() => level = v ?? level),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<StudyMode>(
                  value: mode,
                  decoration: const InputDecoration(labelText: '模式'),
                  items: const [
                    DropdownMenuItem(value: StudyMode.due, child: Text('到期复习（推荐）')),
                    DropdownMenuItem(value: StudyMode.newOnly, child: Text('新词')),
                    DropdownMenuItem(value: StudyMode.all, child: Text('全部随机')),
                  ],
                  onChanged: (v) => setState(() => mode = v ?? mode),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: count,
                  decoration: const InputDecoration(labelText: '数量'),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10')),
                    DropdownMenuItem(value: 20, child: Text('20')),
                    DropdownMenuItem(value: 50, child: Text('50')),
                    DropdownMenuItem(value: 100, child: Text('100')),
                  ],
                  onChanged: (v) => setState(() => count = v ?? count),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: ready
                      ? () async {
                          final db = m.db!;
                          final ids = await pickStudyItemIds(db, deck: deck, level: level, mode: mode, limit: count);
                          if (!context.mounted) return;
                          if (ids.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可学习条目：可换等级或模式')));
                            return;
                          }
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudySessionPage(itemIds: ids, deck: deck, level: level),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始自测'),
                ),
                const SizedBox(height: 8),
                const Text(
                  '评分按钮含义：\n'
                  '忘记=Again（很快再出现）｜困难=Hard｜记住=Good｜秒懂=Easy（间隔更长）',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (!ready)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('提示：请先去【初始化】导入词库并设置媒体目录。'),
          ),
      ],
    );
  }
}

enum StudyMode { due, newOnly, all }

Future<List<int>> pickStudyItemIds(
  Database db, {
  required String deck,
  required String level,
  required StudyMode mode,
  required int limit,
}) async {
  final today = epochDay(DateTime.now());
  if (mode == StudyMode.due) {
    // 到期：due_day<=today
    final rows = await db.rawQuery('''
      SELECT i.id AS id
      FROM items i
      JOIN srs s ON s.item_id=i.id
      WHERE i.deck=? AND i.level=? AND s.due_day<=?
      ORDER BY s.due_day ASC
      LIMIT ?;
    ''', [deck, level, today, limit]);
    return rows.map((e) => (e['id'] as num).toInt()).toList();
  }

  if (mode == StudyMode.newOnly) {
    // 新词：没有 srs 记录
    final rows = await db.rawQuery('''
      SELECT i.id AS id
      FROM items i
      LEFT JOIN srs s ON s.item_id=i.id
      WHERE i.deck=? AND i.level=? AND s.item_id IS NULL
      ORDER BY i.id DESC
      LIMIT ?;
    ''', [deck, level, limit]);
    return rows.map((e) => (e['id'] as num).toInt()).toList();
  }

  // all：随机抽样
  final rows = await db.rawQuery('''
    SELECT i.id AS id
    FROM items i
    WHERE i.deck=? AND i.level=?
    ORDER BY i.id DESC
    LIMIT 500;
  ''', [deck, level]);
  final all = rows.map((e) => (e['id'] as num).toInt()).toList();
  all.shuffle(Random());
  return all.take(limit).toList();
}

class StudySessionPage extends StatefulWidget {
  final List<int> itemIds;
  final String deck;
  final String level;

  const StudySessionPage({super.key, required this.itemIds, required this.deck, required this.level});

  @override
  State<StudySessionPage> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends State<StudySessionPage> {
  int idx = 0;
  bool reveal = false;

  VocabItem? item;
  List<MediaRow> media = [];
  bool loading = true;
  String? err;

  final player = AudioPlayer();
  String? nowPlaying;

  int remembered = 0;
  int forgotten = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    final m = appModelOf(context);
    final db = m.db;
    if (db == null) return;

    setState(() {
      loading = true;
      err = null;
      reveal = false;
    });

    try {
      final id = widget.itemIds[idx];
      final rows = await db.query('items', where: 'id=?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw Exception('找不到条目：$id');

      item = VocabItem.fromMap(rows.first);

      final ms = await db.query('media', where: 'item_id=?', whereArgs: [id]);
      media = ms.map(MediaRow.fromMap).toList();
    } catch (e) {
      err = '加载失败：$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String resolveMediaPath(String raw) {
    final m = appModelOf(context);
    final p = raw.replaceAll('\\', '/');

    const marker = '/にほんご/';
    final i = p.indexOf(marker);
    if (i >= 0) {
      final rel = p.substring(i + marker.length);
      return '${m.baseDir}/$rel';
    }

    final p2 = p.replaceFirst(RegExp(r'^[A-Za-z]:/'), '');
    return '${m.baseDir}/${p2.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Future<void> _playFirstAudio() async {
    final a = media.firstWhere((e) => e.type == 'audio', orElse: () => MediaRow(itemId: 0, type: 'audio', path: ''));
    if (a.path.isEmpty) return;
    final real = resolveMediaPath(a.path);
    final f = File(real);
    if (!await f.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频不存在：$real')));
      return;
    }
    await player.setFilePath(real);
    await player.play();
    setState(() => nowPlaying = real);
  }

  Future<void> _answer(int grade) async {
    // grade: 1..4
    final m = appModelOf(context);
    final db = m.db!;
    final today = epochDay(DateTime.now());
    final id = widget.itemIds[idx];

    // 读取 srs
    final srsRows = await db.query('srs', where: 'item_id=?', whereArgs: [id], limit: 1);
    double ease = 2.5;
    int interval = 0;
    int reps = 0;
    int lapses = 0;

    if (srsRows.isNotEmpty) {
      final r = srsRows.first;
      ease = (r['ease'] as num).toDouble();
      interval = (r['interval_days'] as num).toInt();
      reps = (r['reps'] as num).toInt();
      lapses = (r['lapses'] as num).toInt();
    }

    final upd = sm2Update(
      today: today,
      ease: ease,
      intervalDays: interval,
      reps: reps,
      lapses: lapses,
      grade: grade,
    );

    await db.transaction((txn) async {
      await txn.execute(
        '''
        INSERT INTO srs(item_id,deck,level,state,ease,interval_days,due_day,reps,lapses,last_review_day)
        VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(item_id) DO UPDATE SET
          deck=excluded.deck,
          level=excluded.level,
          state=excluded.state,
          ease=excluded.ease,
          interval_days=excluded.interval_days,
          due_day=excluded.due_day,
          reps=excluded.reps,
          lapses=excluded.lapses,
          last_review_day=excluded.last_review_day;
        ''',
        [
          id,
          widget.deck,
          widget.level,
          upd.state,
          upd.ease,
          upd.intervalDays,
          upd.dueDay,
          upd.reps,
          upd.lapses,
          today,
        ],
      );

      await txn.insert('review_log', {
        'item_id': id,
        'day': today,
        'grade': grade,
        'ts': unixSeconds(),
      });
    });

    if (grade <= 1) {
      forgotten += 1;
    } else {
      remembered += 1;
    }

    // 下一题
    if (idx < widget.itemIds.length - 1) {
      setState(() => idx += 1);
      await _loadCurrent();
    } else {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('本次自测完成'),
          content: Text('总数：${widget.itemIds.length}\n记住：$remembered\n忘记：$forgotten'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('确定')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.itemIds.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('自测 ${idx + 1}/$total'),
        actions: [
          IconButton(
            tooltip: '显示/隐藏答案',
            onPressed: () => setState(() => reveal = !reveal),
            icon: Icon(reveal ? Icons.visibility_off : Icons.visibility),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(child: Text(err!))
              : _buildCard(),
    );
  }

  Widget _buildCard() {
    final it = item!;
    final img = media.firstWhere((e) => e.type == 'image', orElse: () => MediaRow(itemId: 0, type: 'image', path: ''));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.term, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (it.reading.isNotEmpty) Text('かな：${it.reading}', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Chip(label: Text(it.level.isEmpty ? 'N?' : it.level)),
                    const SizedBox(width: 8),
                    Chip(label: Text(it.deck)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _playFirstAudio,
                      icon: const Icon(Icons.volume_up),
                      label: const Text('播放音频'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => reveal = !reveal),
                      icon: Icon(reveal ? Icons.visibility_off : Icons.visibility),
                      label: Text(reveal ? '隐藏答案' : '显示答案'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (reveal && img.path.isNotEmpty) _ImageBlock(path: resolveMediaPath(img.path)),
        if (reveal && img.path.isNotEmpty) const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('你的回答', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => _answer(1), child: const Text('忘记'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: () => _answer(2), child: const Text('困难'))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: FilledButton(onPressed: () => _answer(3), child: const Text('记住'))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(onPressed: () => _answer(4), child: const Text('秒懂'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageBlock extends StatelessWidget {
  final String path;
  const _ImageBlock({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: File(path).exists(),
      builder: (_, snap) {
        final ok = snap.data == true;
        if (!ok) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('图片不存在：$path', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }
}
