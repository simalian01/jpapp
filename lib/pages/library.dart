import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../db.dart';

enum MemoryFilter { all, newOnly, dueOnly, learnedOnly, masteredOnly }

extension MemoryFilterLabel on MemoryFilter {
  String get label {
    switch (this) {
      case MemoryFilter.all:
        return '全部';
      case MemoryFilter.newOnly:
        return '新词';
      case MemoryFilter.dueOnly:
        return '待复习';
      case MemoryFilter.learnedOnly:
        return '已学习';
      case MemoryFilter.masteredOnly:
        return '已掌握';
    }
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  Database? _lastDb;

  List<String> decks = [];
  List<String> levels = ['全部'];

  String deck = '';
  String level = '全部';
  MemoryFilter memFilter = MemoryFilter.all;

  String query = '';
  Timer? _debounce;

  final ScrollController _sc = ScrollController();
  final List<Map<String, Object?>> items = [];
  bool loading = false;
  bool hasMore = true;
  int offset = 0;
  static const pageSize = 60;

  int _shuffleSeed = 0;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (_sc.position.pixels >= _sc.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

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

  @override
  void dispose() {
    _debounce?.cancel();
    _sc.dispose();
    super.dispose();
  }

  Future<void> _loadMeta(Database db) async {
    final deckRows = await db.rawQuery("""
      SELECT DISTINCT deck FROM items
      ORDER BY deck;
    """);
    decks = deckRows.map((e) => (e['deck'] as String).trim()).where((s) => s.isNotEmpty).toList();
    if (decks.isEmpty) return;

    deck = decks.contains('红宝书') ? '红宝书' : decks.first;
    await _loadLevels(db, deck);

    if (!mounted) return;
    setState(() {});
    await _reload();
  }

  Future<void> _loadLevels(Database db, String deck) async {
    final rows = await db.rawQuery("""
      SELECT DISTINCT level FROM items
      WHERE deck=? AND level IS NOT NULL AND TRIM(level)!=''
      ORDER BY level;
    """, [deck]);

    final lv = rows.map((e) => (e['level'] as String).trim()).where((s) => s.isNotEmpty).toList();
    levels = ['全部', ...lv];
    level = '全部';
  }

  Future<void> _reload() async {
    setState(() {
      items.clear();
      offset = 0;
      hasMore = true;
    });
    await _loadMore();
  }

  void _shuffleNow() {
    setState(() {
      _shuffleSeed++;
      items.shuffle(Random(DateTime.now().millisecondsSinceEpoch ^ _shuffleSeed));
    });
  }

  Future<void> _loadMore() async {
    if (loading || !hasMore) return;

    final m = appModelOf(context);
    final db = m.db;
    if (db == null) return;

    setState(() => loading = true);
    try {
      final rows = await _queryItems(
        db: db,
        deck: deck,
        level: level,
        q: query,
        mem: memFilter,
        offset: offset,
        limit: pageSize,
      );
      setState(() {
        items.addAll(rows);
        offset += rows.length;
        hasMore = rows.length == pageSize;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<Map<String, Object?>>> _queryItems({
    required Database db,
    required String deck,
    required String level,
    required String q,
    required MemoryFilter mem,
    required int offset,
    required int limit,
  }) async {
    final today = epochDay(DateTime.now());
    final where = <String>['i.deck=?'];
    final args = <Object?>[deck];

    if (level != '全部') {
      where.add('i.level=?');
      args.add(level);
    }

    switch (mem) {
      case MemoryFilter.all:
        break;
      case MemoryFilter.newOnly:
        where.add('s.item_id IS NULL');
        break;
      case MemoryFilter.dueOnly:
        where.add('s.item_id IS NOT NULL AND s.due_day <= ?');
        args.add(today);
        break;
      case MemoryFilter.learnedOnly:
        where.add('s.item_id IS NOT NULL');
        break;
      case MemoryFilter.masteredOnly:
        where.add('s.item_id IS NOT NULL AND s.reps >= 4 AND s.interval_days >= 21 AND s.due_day > ?');
        args.add(today);
        break;
    }

    final qq = q.trim();
    if (qq.isNotEmpty) {
      where.add('i.search_text LIKE ?');
      args.add('%$qq%');
    }

    final sql = '''
      SELECT i.id, i.term, i.reading, i.level,
             COALESCE(s.reps,0) AS reps,
             COALESCE(s.interval_days,0) AS interval_days,
             COALESCE(s.due_day,0) AS due_day,
             CASE
               WHEN s.item_id IS NULL THEN 0
               WHEN s.due_day <= $today THEN 1
               WHEN s.reps >= 4 AND s.interval_days >= 21 AND s.due_day > $today THEN 3
               ELSE 2
             END AS mem_tag
      FROM items i
      LEFT JOIN srs s ON s.item_id=i.id
      WHERE ${where.join(' AND ')}
      ORDER BY i.id DESC
      LIMIT ? OFFSET ?;
    ''';

    return db.rawQuery(sql, [...args, limit, offset]);
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);
    final ready = m.db != null && m.error == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('词库'),
        actions: [
          IconButton(
            tooltip: '重新打乱当前列表',
            onPressed: items.isEmpty ? null : _shuffleNow,
            icon: const Icon(Icons.shuffle_rounded),
          ),
          IconButton(
            tooltip: '重新加载',
            onPressed: ready ? _reload : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7F4FF), Color(0xFFFDFDFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CustomScrollView(
          controller: _sc,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: deck.isEmpty ? null : deck,
                                decoration: const InputDecoration(labelText: '词库/书'),
                                items: decks
                                    .map((d) => DropdownMenuItem(
                                          value: d,
                                          child: Text(d, overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: !ready
                                    ? null
                                    : (v) async {
                                        if (v == null) return;
                                        setState(() => deck = v);
                                        await _loadLevels(m.db!, deck);
                                        await _reload();
                                      },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: level,
                                decoration: const InputDecoration(labelText: '等级（可不筛）'),
                                items: levels
                                    .map((lv) => DropdownMenuItem(value: lv, child: Text(lv)))
                                    .toList(),
                                onChanged: !ready
                                    ? null
                                    : (v) async {
                                        setState(() => level = v ?? '全部');
                                        await _reload();
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<MemoryFilter>(
                                value: memFilter,
                                decoration: const InputDecoration(labelText: '记忆筛选'),
                                items: MemoryFilter.values
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                                    .toList(),
                                onChanged: !ready
                                    ? null
                                    : (v) async {
                                        setState(() => memFilter = v ?? memFilter);
                                        await _reload();
                                      },
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filledTonal(
                              tooltip: '打乱（反复点击反复随机）',
                              onPressed: items.isEmpty ? null : _shuffleNow,
                              icon: const Icon(Icons.casino),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          enabled: ready,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索（假名/汉字/关键词）',
                          ),
                          onChanged: (v) {
                            _debounce?.cancel();
                            _debounce = Timer(const Duration(milliseconds: 250), () async {
                              setState(() => query = v);
                              await _reload();
                            });
                          },
                        ),
                        if (!ready)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('请先在【初始化】导入词库', style: TextStyle(color: Colors.redAccent)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  if (i == items.length) {
                    if (loading) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!hasMore) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('没有更多了')),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final row = items[i];
                  final id = (row['id'] as num).toInt();
                  final term = (row['term'] as String?) ?? '';
                  final reading = (row['reading'] as String?) ?? '';
                  final levelLabel = (row['level'] as String?) ?? '';
                  final memTag = (row['mem_tag'] as num?)?.toInt() ?? 0;

                  final label = switch (memTag) {
                    0 => '新词',
                    1 => '待复习',
                    3 => '已掌握',
                    _ => '已学习',
                  };

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        title: Text(term, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reading.isNotEmpty) Text(reading),
                            if (levelLabel.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('等级：$levelLabel', style: const TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(label),
                          avatar: Icon(
                            memTag == 0
                                ? Icons.fiber_new_rounded
                                : memTag == 3
                                    ? Icons.workspace_premium
                                    : Icons.refresh,
                            size: 18,
                          ),
                        ),
                        onTap: () async {
                          final db = m.db;
                          if (db == null) return;

                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailPage(db: db, itemId: id, baseDir: m.baseDir),
                            ),
                          );

                          await _reload();
                        },
                      ),
                    ),
                  );
                },
                childCount: items.length + 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ 不转圈详情页（db/baseDir 由构造传入）
class ItemDetailPage extends StatefulWidget {
  final Database db;
  final int itemId;
  final String baseDir;

  const ItemDetailPage({
    super.key,
    required this.db,
    required this.itemId,
    required this.baseDir,
  });

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  Map<String, Object?>? item;
  Map<String, Object?>? srs;
  List<Map<String, Object?>> media = [];

  String? audioPath;
  String? imagePath;
  bool audioExists = false;
  bool imageExists = false;

  bool loading = true;
  String? err;

  final player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String resolveMediaPath(String raw) {
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

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });

    try {
      final it = await widget.db.query('items', where: 'id=?', whereArgs: [widget.itemId], limit: 1);
      if (it.isEmpty) throw Exception('找不到条目');
      item = it.first;

      media = await widget.db.query('media', where: 'item_id=?', whereArgs: [widget.itemId]);
      final sr = await widget.db.query('srs', where: 'item_id=?', whereArgs: [widget.itemId], limit: 1);
      srs = sr.isEmpty ? null : sr.first;

      final a = media.where((e) => e['type'] == 'audio').toList();
      final img = media.where((e) => e['type'] == 'image').toList();

      audioPath = a.isEmpty ? null : resolveMediaPath((a.first['path'] as String).trim());
      imagePath = img.isEmpty ? null : resolveMediaPath((img.first['path'] as String).trim());

      audioExists = audioPath != null && File(audioPath!).existsSync();
      imageExists = imagePath != null && File(imagePath!).existsSync();
    } catch (e) {
      err = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _playAudio() async {
    if (audioPath == null || !audioExists) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频不存在：${audioPath ?? "(空)"}')));
      return;
    }
    await player.setFilePath(audioPath!);
    await player.play();
  }

  @override
  Widget build(BuildContext context) {
    final it = item;

    return Scaffold(
      appBar: AppBar(
        title: const Text('详情'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
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
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((it?['term'] as String?) ?? '',
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text('かな：${(it?['reading'] as String?) ?? ''}'),
                            const SizedBox(height: 6),
                            Text('等级：${(it?['level'] as String?) ?? ''}'),
                            const SizedBox(height: 6),
                            Text('释义：${(it?['meaning'] as String?) ?? ''}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _playAudio,
                          icon: const Icon(Icons.volume_up),
                          label: Text(audioExists ? '播放音频' : '音频缺失'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (imagePath == null || !imageExists) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('图片不存在：${imagePath ?? "(空)"}')));
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
                          padding: const EdgeInsets.all(12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(imagePath!), fit: BoxFit.contain),
                          ),
                        ),
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
