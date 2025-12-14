import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../db.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String deck = '红宝书';
  String level = 'N5';
  String query = '';
  Timer? _debounce;

  final ScrollController _sc = ScrollController();
  final List<Map<String, Object?>> items = [];
  bool loading = false;
  bool hasMore = true;
  int offset = 0;
  static const pageSize = 50;

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
  void dispose() {
    _debounce?.cancel();
    _sc.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      items.clear();
      offset = 0;
      hasMore = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (loading || !hasMore) return;
    final m = appModelOf(context);
    final db = m.db;
    if (db == null) return;

    setState(() => loading = true);
    try {
      final rows = await _queryItems(db, deck, level, query, offset, pageSize);
      setState(() {
        items.addAll(rows);
        offset += rows.length;
        hasMore = rows.length == pageSize;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<Map<String, Object?>>> _queryItems(
    Database db,
    String deck,
    String level,
    String q,
    int offset,
    int limit,
  ) async {
    final qq = q.trim();
    if (qq.isEmpty) {
      return db.rawQuery('''
        SELECT i.id, i.term, i.reading, i.level,
               COALESCE(s.reps,0) AS reps,
               COALESCE(s.due_day,0) AS due_day
        FROM items i
        LEFT JOIN srs s ON s.item_id=i.id
        WHERE i.deck=? AND i.level=?
        ORDER BY i.id DESC
        LIMIT ? OFFSET ?;
      ''', [deck, level, limit, offset]);
    }

    // ✅ 用 LIKE + search_text 索引，速度会明显好
    final like = '%$qq%';
    return db.rawQuery('''
      SELECT i.id, i.term, i.reading, i.level,
             COALESCE(s.reps,0) AS reps,
             COALESCE(s.due_day,0) AS due_day
      FROM items i
      LEFT JOIN srs s ON s.item_id=i.id
      WHERE i.deck=? AND i.level=? AND i.search_text LIKE ?
      ORDER BY i.id DESC
      LIMIT ? OFFSET ?;
    ''', [deck, level, like, limit, offset]);
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);
    final ready = m.db != null && m.error == null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: deck,
                      decoration: const InputDecoration(labelText: '词库/书'),
                      items: const [DropdownMenuItem(value: '红宝书', child: Text('红宝书'))],
                      onChanged: (v) async {
                        setState(() => deck = v ?? deck);
                        await _reload();
                      },
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
                      onChanged: (v) async {
                        setState(() => level = v ?? level);
                        await _reload();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                enabled: ready,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索（假名/汉字/关键词）',
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () async {
                    setState(() => query = v);
                    await _reload();
                  });
                },
              ),
              const SizedBox(height: 8),
              if (!ready) const Text('请先在【初始化】导入词库'),
              if (ready && items.isEmpty && !loading)
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('加载词库列表'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _sc,
            itemCount: items.length + 1,
            itemBuilder: (_, i) {
              if (i == items.length) {
                if (loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                if (!hasMore) return const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('没有更多了')));
                return const SizedBox.shrink();
              }

              final row = items[i];
              final id = (row['id'] as num).toInt();
              final term = (row['term'] as String?) ?? '';
              final reading = (row['reading'] as String?) ?? '';
              final reps = (row['reps'] as num?)?.toInt() ?? 0;
              final dueDay = (row['due_day'] as num?)?.toInt() ?? 0;

              final today = epochDay(DateTime.now());
              final status = reps == 0 ? '新词' : (dueDay <= today ? '到期' : '已学');
              final color = status == '到期'
                  ? Colors.orange
                  : (status == '新词' ? Colors.blueGrey : Colors.green);

              return ListTile(
                title: Text(term),
                subtitle: Text(reading.isEmpty ? status : '$reading  ·  $status'),
                trailing: Chip(label: Text(status), backgroundColor: color.withOpacity(0.15)),
                onTap: () async {
                  final m = appModelOf(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: id, baseDir: m.baseDir)),
                  );
                  // 返回后刷新（可能背诵状态变了）
                  await _reload();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class ItemDetailPage extends StatefulWidget {
  final int itemId;
  final String baseDir;

  const ItemDetailPage({super.key, required this.itemId, required this.baseDir});

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  Map<String, Object?>? item;
  List<Map<String, Object?>> media = [];
  Map<String, Object?>? srs;

  bool loading = true;
  String? err;

  final player = AudioPlayer();

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final m = appModelOf(context);
    final db = m.db;
    if (db == null) return;

    setState(() {
      loading = true;
      err = null;
    });

    try {
      final it = await db.query('items', where: 'id=?', whereArgs: [widget.itemId], limit: 1);
      if (it.isEmpty) throw Exception('找不到单词');
      item = it.first;

      media = await db.query('media', where: 'item_id=?', whereArgs: [widget.itemId]);
      final sr = await db.query('srs', where: 'item_id=?', whereArgs: [widget.itemId], limit: 1);
      srs = sr.isEmpty ? null : sr.first;
    } catch (e) {
      err = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _playAudio() async {
    final a = media.firstWhere((e) => e['type'] == 'audio', orElse: () => {});
    if (a.isEmpty) return;
    final path = resolveMediaPath((a['path'] as String).trim());
    final f = File(path);
    if (!await f.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频不存在：$path')));
      return;
    }
    await player.setFilePath(path);
    await player.play();
  }

  @override
  Widget build(BuildContext context) {
    final it = item;

    return Scaffold(
      appBar: AppBar(title: const Text('单词详情')),
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
                            Text((it?['term'] as String?) ?? '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text('かな：${(it?['reading'] as String?) ?? ''}'),
                            const SizedBox(height: 6),
                            Text('等级：${(it?['level'] as String?) ?? ''}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('记忆状态', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            if (srs == null)
                              const Text('尚未学习（新词）')
                            else ...[
                              Text('复习次数 reps：${(srs!['reps'] as num).toInt()}'),
                              Text('间隔 interval_days：${(srs!['interval_days'] as num).toInt()} 天'),
                              Text('到期 due_day：${(srs!['due_day'] as num).toInt()}（天数戳）'),
                              Text('难度 ease：${(srs!['ease'] as num).toDouble().toStringAsFixed(2)}'),
                            ],
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
                          label: const Text('播放音频'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildImage(),
                  ],
                ),
    );
  }

  Widget _buildImage() {
    final img = media.firstWhere((e) => e['type'] == 'image', orElse: () => {});
    if (img.isEmpty) return const SizedBox.shrink();

    final path = resolveMediaPath((img['path'] as String).trim());
    return FutureBuilder<bool>(
      future: File(path).exists(),
      builder: (_, snap) {
        if (snap.data != true) {
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('图片不存在：$path')));
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
