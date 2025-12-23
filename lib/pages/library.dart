import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../db.dart';
import '../utils/media_path.dart';
import 'carousel.dart';

enum MemoryFilter { all, remembered, forgotten, fresh }

extension MemoryFilterLabel on MemoryFilter {
  String get label {
    switch (this) {
      case MemoryFilter.all:
        return '全部';
      case MemoryFilter.remembered:
        return '记得';
      case MemoryFilter.forgotten:
        return '不记得';
      case MemoryFilter.fresh:
        return '未标记';
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
  bool shuffle = false;

  String query = '';
  Timer? _debounce;

  final ScrollController _sc = ScrollController();
  final List<Map<String, Object?>> items = [];
  bool loading = false;
  String? err;

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
      WHERE deck IN ('红宝书','蓝宝书')
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
      loading = true;
      err = null;
    });

    try {
      final m = appModelOf(context);
      final db = m.db;
      if (db == null) throw Exception('数据库未准备好');

      final rows = await _queryItems(
        db: db,
        deck: deck,
        level: level,
        q: query,
        mem: memFilter,
        shuffle: shuffle,
      );
      setState(() {
        items
          ..clear()
          ..addAll(rows);
      });
    } catch (e) {
      err = '$e';
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
    required bool shuffle,
  }) async {
    final where = <String>['i.deck=?'];
    final args = <Object?>[deck];

    if (level != '全部') {
      where.add('i.level=?');
      args.add(level);
    }

    final qq = q.trim();
    if (qq.isNotEmpty) {
      where.add('i.search_text LIKE ?');
      args.add('%$qq%');
    }

    String memClause = '';
    switch (mem) {
      case MemoryFilter.all:
        break;
      case MemoryFilter.remembered:
        memClause = 'AND s.reps >= 1';
        break;
      case MemoryFilter.forgotten:
        memClause = 'AND s.reps < 0';
        break;
      case MemoryFilter.fresh:
        memClause = 'AND s.item_id IS NULL';
        break;
    }

    final orderClause = shuffle ? 'ORDER BY RANDOM()' : 'ORDER BY i.id DESC';
    final sql = '''
      SELECT i.id, i.term, i.reading, i.level,
             COALESCE(s.reps,0) AS reps,
             COALESCE(s.interval_days,0) AS interval_days,
             COALESCE(s.due_day,0) AS due_day
      FROM items i
      LEFT JOIN srs s ON s.item_id=i.id
      WHERE ${where.join(' AND ')} $memClause
      $orderClause;
    ''';

    return db.rawQuery(sql, args);
  }

  Future<void> _markMemory(int itemId, bool remember) async {
    final m = appModelOf(context);
    final db = m.db;
    if (db == null) return;

    final today = epochDay(DateTime.now());
    final exist = await db.query('srs', where: 'item_id=?', whereArgs: [itemId]);
    double ease = exist.isEmpty ? 2.5 : (exist.first['ease'] as num).toDouble();
    int interval = exist.isEmpty ? 0 : (exist.first['interval_days'] as num).toInt();
    int reps = exist.isEmpty ? 0 : (exist.first['reps'] as num).toInt();
    int lapses = exist.isEmpty ? 0 : (exist.first['lapses'] as num).toInt();

    final upd = sm2Update(
      today: today,
      ease: ease,
      intervalDays: interval,
      reps: reps,
      lapses: lapses,
      grade: remember ? 4 : 1,
    );

    final storedReps = remember ? upd.reps : -1;

    await db.insert(
      'srs',
      {
        'item_id': itemId,
        'deck': deck,
        'level': level == '全部' ? null : level,
        'ease': upd.ease,
        'interval_days': upd.intervalDays,
        'reps': storedReps,
        'lapses': upd.lapses,
        'due_day': upd.dueDay,
        'state': upd.state,
        'last_review_day': today,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert(
      'review_log',
      {
        'item_id': itemId,
        'day': today,
        'grade': remember ? 4 : 1,
        'ts': unixSeconds(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await m.logUsage(
      remembered: remember ? 1 : 0,
      forgotten: remember ? 0 : 1,
    );

    setState(() {
      final idx = items.indexWhere((e) => (e['id'] as num).toInt() == itemId);
      if (idx >= 0) {
        items[idx]['reps'] = storedReps;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);
    final ready = m.db != null && m.error == null;

    return Scaffold(
      floatingActionButton: ready
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.slideshow),
              label: const Text('轮换播放'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CarouselPlayerPage(initialDeck: deck.isEmpty ? null : deck),
                  ),
                );
              },
            )
          : null,
      body: ready
          ? NestedScrollView(
              controller: _sc,
              headerSliverBuilder: (_, __) => [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  pinned: false,
                  expandedHeight: 340,
                  flexibleSpace: FlexibleSpaceBar(
                    background: SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 60, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('红/蓝双书全集，直出列表，滑动即可专注记忆',
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: deck.isEmpty ? null : deck,
                                    decoration: const InputDecoration(labelText: '词书'),
                                    items: decks
                                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                                        .toList(),
                                    onChanged: (v) async {
                                      if (v == null) return;
                                      setState(() => deck = v);
                                      await _loadLevels(m.db!, deck);
                                      await _reload();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: level,
                                    decoration: const InputDecoration(labelText: '等级'),
                                    items: levels
                                        .map((lv) => DropdownMenuItem(value: lv, child: Text(lv)))
                                        .toList(),
                                    onChanged: (v) async {
                                      setState(() => level = v ?? '全部');
                                      await _reload();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 42,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final mf in MemoryFilter.values)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(mf.label),
                                        selected: memFilter == mf,
                                        onSelected: (_) async {
                                          setState(() => memFilter = mf);
                                          await _reload();
                                        },
                                      ),
                                    ),
                                OutlinedButton.icon(
                                  onPressed: _reload,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('重载'),
                                ),
                                const SizedBox(width: 8),
                                FilterChip(
                                  selected: shuffle,
                                  label: const Text('打乱顺序'),
                                  onSelected: (v) async {
                                    setState(() => shuffle = v);
                                    await _reload();
                                  },
                                ),
                              ],
                            ),
                          ),
                            const SizedBox(height: 10),
                            TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: '直接查找假名/汉字/释义',
                                filled: true,
                              ),
                              onChanged: (v) {
                                _debounce?.cancel();
                                _debounce = Timer(const Duration(milliseconds: 250), () async {
                                  setState(() => query = v);
                                  await _reload();
                                });
                              },
                            ),
                            const SizedBox(height: 6),
                            Text('当前列表：${items.length} 条', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              body: RefreshIndicator(
                onRefresh: _reload,
                child: err != null
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        ],
                      )
                    : ListView.builder(
                        key: const PageStorageKey('memory-list'),
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final row = items[i];
                          final id = (row['id'] as num).toInt();
                          final term = (row['term'] as String?) ?? '';
                          final reading = (row['reading'] as String?) ?? '';
                          final reps = (row['reps'] as num?)?.toInt() ?? 0;
                          final remembered = reps > 0;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text(term, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: reading.isNotEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(reading, style: const TextStyle(fontSize: 13)),
                                    )
                                  : null,
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  FilterChip(
                                    label: const Text('记得'),
                                    selected: remembered,
                                    onSelected: (_) => _markMemory(id, true),
                                  ),
                                  FilterChip(
                                    label: const Text('不记得'),
                                    selected: !remembered && reps != 0,
                                    onSelected: (_) => _markMemory(id, false),
                                  ),
                                ],
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
                              },
                            ),
                          );
                        },
                      ),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
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
  Map<String, String> dataFields = {};

  String? audioPath;
  String? imagePath;
  bool audioExists = false;
  bool imageExists = false;

  bool _loggedOpen = false;

  bool loading = true;
  String? err;

  Set<String>? _itemColumns;

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

  Future<Set<String>> _loadItemColumns() async {
    if (_itemColumns != null) return _itemColumns!;
    final rows = await widget.db.rawQuery("PRAGMA table_info(items);");
    _itemColumns = rows.map((e) => (e['name'] as String?) ?? '').toSet();
    return _itemColumns!;
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });

    try {
      if (!_loggedOpen) {
        await appModelOf(context).logUsage(detailOpens: 1);
        _loggedOpen = true;
      }

      final columns = ['id', 'deck', 'term', 'reading', 'level', 'meaning'];
      final cols = await _loadItemColumns();
      if (cols.contains('sheet')) columns.add('sheet');
      if (cols.contains('data_json')) columns.add('data_json');

      final it = await widget.db.query('items', columns: columns, where: 'id=?', whereArgs: [widget.itemId], limit: 1);
      if (it.isEmpty) throw Exception('找不到条目');
      item = it.first;

      media = await widget.db.query('media', where: 'item_id=?', whereArgs: [widget.itemId]);
      final sr = await widget.db.query('srs', where: 'item_id=?', whereArgs: [widget.itemId], limit: 1);
      srs = sr.isEmpty ? null : sr.first;

      dataFields = {};
      final rawJson = (item?['data_json'] as String?) ?? '';
      if (rawJson.isNotEmpty) {
        try {
          final obj = jsonDecode(rawJson);
          if (obj is Map) {
            dataFields = obj.map((k, v) => MapEntry('$k', '${v ?? ''}'));
          }
        } catch (_) {
          // ignore parsing errors; fallback to empty map
        }
      }

      final a = media.where((e) => e['type'] == 'audio').toList();
      final img = media.where((e) => e['type'] == 'image').toList();

      audioPath = a.isEmpty ? null : resolveMediaPath((a.first['path'] as String).trim(), widget.baseDir);
      imagePath = img.isEmpty ? null : resolveMediaPath((img.first['path'] as String).trim(), widget.baseDir);

      audioExists = audioPath != null && File(audioPath!).existsSync();
      imageExists = imagePath != null && File(imagePath!).existsSync();
    } catch (e) {
      err = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, String> _deckSpecificFields(String deck) {
    if (dataFields.isEmpty) return {};
    switch (deck) {
      case '红宝书':
        return {
          if (dataFields['汉字/外文']?.trim().isNotEmpty == true) '汉字/外文': dataFields['汉字/外文']!,
          if (dataFields['假名']?.trim().isNotEmpty == true) '假名': dataFields['假名']!,
          if (dataFields['等级']?.trim().isNotEmpty == true) '等级': dataFields['等级']!,
          if (dataFields['图源路径']?.trim().isNotEmpty == true) '图片路径': dataFields['图源路径']!,
          if (dataFields['音源路径']?.trim().isNotEmpty == true) '音频路径': dataFields['音源路径']!,
        };
      case '日语汉字':
        return {
          if (dataFields['漢字']?.trim().isNotEmpty == true) '漢字': dataFields['漢字']!,
          if (dataFields['音訓']?.trim().isNotEmpty == true) '音訓': dataFields['音訓']!,
          if (dataFields['漢字表・例']?.trim().isNotEmpty == true) '例': dataFields['漢字表・例']!,
        };
      default:
        return Map.of(dataFields);
    }
  }

  Widget _buildInfoTable(Map<String, String> fields) {
    if (fields.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: const Text('补充信息（路径信息，如无需要可不展开）'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: fields.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 90, child: Text('${e.key}：', style: const TextStyle(color: Colors.grey))),
                    Expanded(child: Text(e.value)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
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
    final meaningText = ((it?['meaning'] as String?) ?? '').trim();
    final deckName = (item?['sheet'] as String?) ?? (item?['deck'] as String?) ?? '';
    final infoTable = _buildInfoTable(_deckSpecificFields(deckName));

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
                            if (((it?['reading'] as String?) ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('かな：${(it?['reading'] as String?) ?? ''}'),
                              ),
                            if (((it?['level'] as String?) ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('等级：${(it?['level'] as String?) ?? ''}'),
                              ),
                            if (meaningText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('释义：'),
                                    const SizedBox(height: 4),
                                    ...meaningText.split('\n').map((line) => Text(line)).toList(),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (audioExists)
                          FilledButton.icon(
                            onPressed: _playAudio,
                            icon: const Icon(Icons.volume_up),
                            label: const Text('播放音频'),
                          ),
                        if (imageExists)
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => _ImageViewer(path: imagePath!)),
                              );
                            },
                            icon: const Icon(Icons.image),
                            label: const Text('查看图片'),
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
                    infoTable,
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
