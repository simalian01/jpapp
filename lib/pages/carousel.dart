import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../db.dart';
import '../utils/media_path.dart';

class _CarouselItem {
  final int id;
  final String term;
  final String reading;
  final String meaning;
  final String? audioPath;
  final String? imagePath;

  const _CarouselItem({
    required this.id,
    required this.term,
    required this.reading,
    required this.meaning,
    required this.audioPath,
    required this.imagePath,
  });
}

class CarouselRun {
  final int id;
  final DateTime createdAt;
  final String? deck;
  final String? level;
  final int? count;
  final bool shuffle;
  final List<int> itemIds;

  const CarouselRun({
    required this.id,
    required this.createdAt,
    required this.deck,
    required this.level,
    required this.count,
    required this.shuffle,
    required this.itemIds,
  });

  factory CarouselRun.fromRow(Map<String, Object?> row) {
    final idsText = (row['item_ids'] as String?) ?? '';
    final ids = idsText
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    return CarouselRun(
      id: (row['id'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(((row['created_at'] as num?)?.toInt() ?? 0) * 1000),
      deck: row['deck'] as String?,
      level: row['level'] as String?,
      count: (row['count'] as num?)?.toInt(),
      shuffle: (row['shuffle'] as num?) == 1,
      itemIds: ids,
    );
  }
}

class CarouselPlayerPage extends StatefulWidget {
  final String? initialDeck;
  const CarouselPlayerPage({super.key, this.initialDeck});

  @override
  State<CarouselPlayerPage> createState() => _CarouselPlayerPageState();
}

class _CarouselPlayerPageState extends State<CarouselPlayerPage> {
  Database? _db;
  String? deck;
  List<String> decks = [];
  List<String> levels = ['全部'];
  String level = '全部';

  final TextEditingController _countCtrl = TextEditingController(text: '20');
  bool shuffle = true;
  bool loopPlaylist = true;
  bool reshuffleOnLoop = true;
  double wordGapSeconds = 2.5;
  double repeatGapSeconds = 0.8;
  int playTimes = 1;
  double gain = 1.0;
  bool immersiveImage = false;

  List<_CarouselItem> playlist = [];
  List<CarouselRun> history = [];
  bool loading = false;
  bool playing = false;
  int currentIndex = 0;
  bool _autoLooping = false;
  bool _stopping = false;
  bool _announcedMissingAudio = false;

  final PageController _pc = PageController();
  final AudioPlayer _player = AudioPlayer();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = appModelOf(context);
    final db = m.db;
    if (db != null && !identical(db, _db)) {
      _db = db;
      _loadMeta();
    }
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _pc.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final db = _db;
    if (db == null) return;
    final rows = await db.rawQuery("""
      SELECT DISTINCT deck FROM items
      WHERE deck IN ('红宝书','蓝宝书')
      ORDER BY deck;
    """);
    decks = rows.map((e) => (e['deck'] as String?) ?? '').where((e) => e.isNotEmpty).toList();
    deck = widget.initialDeck != null && decks.contains(widget.initialDeck)
        ? widget.initialDeck
        : (decks.isNotEmpty ? decks.first : null);
    if (deck != null) await _loadLevels(deck!);
    await _loadHistory();
    if (mounted) setState(() {});
    await _refreshPlaylist();
  }

  Future<void> _loadLevels(String d) async {
    final db = _db;
    if (db == null) return;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT level FROM items
      WHERE deck=? AND level IS NOT NULL AND TRIM(level)!=''
      ORDER BY level;
      '''.
          trim(),
      [d],
    );
    levels = ['全部', ...rows.map((e) => (e['level'] as String?)?.trim() ?? '').where((v) => v.isNotEmpty)];
    if (!levels.contains(level)) level = '全部';
  }

  Future<void> _loadHistory() async {
    final db = _db;
    if (db == null) return;
    final rows = await db.query('carousel_runs', orderBy: 'created_at DESC', limit: 10);
    history = rows.map(CarouselRun.fromRow).toList();
    if (mounted) setState(() {});
  }

  Future<void> _refreshPlaylist() async {
    final db = _db;
    final d = deck;
    if (db == null || d == null) return;

    setState(() {
      loading = true;
    });

    try {
      final where = ['deck=?'];
      final args = <Object?>[d];
      if (level != '全部') {
        where.add('level=?');
        args.add(level);
      }

      final order = shuffle ? 'RANDOM()' : 'id DESC';
      final requestedCount = int.tryParse(_countCtrl.text.trim());
      final limit = requestedCount != null && requestedCount > 0 ? requestedCount : null;
      if (limit != null) args.add(limit);

      final rows = await db.rawQuery(
        '''
        SELECT id, term, reading, meaning, level
        FROM items
        WHERE ${where.join(' AND ')}
        ORDER BY $order
        ${limit != null ? 'LIMIT ?' : ''};
        '''.
            trim(),
        args,
      );
      final baseDir = appModelOf(context).baseDir;

      final items = <_CarouselItem>[];
      for (final r in rows) {
        final id = (r['id'] as num).toInt();
        final medias = await db.query('media', where: 'item_id=?', whereArgs: [id]);
        String? audio;
        String? image;
        for (final m in medias) {
          final type = (m['type'] as String?) ?? '';
          final raw = (m['path'] as String?)?.trim() ?? '';
          if (raw.isEmpty) continue;
          final resolved = resolveMediaPath(raw, baseDir);
          if (type == 'audio' && audio == null && File(resolved).existsSync()) {
            audio = resolved;
          } else if (type == 'image' && image == null && File(resolved).existsSync()) {
            image = resolved;
          }
        }
        items.add(
          _CarouselItem(
            id: id,
            term: (r['term'] as String?) ?? '',
            reading: (r['reading'] as String?) ?? '',
            meaning: (r['meaning'] as String?) ?? '',
            audioPath: audio,
            imagePath: image,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        playlist = items;
        currentIndex = 0;
        _announcedMissingAudio = false;
      });
      if (playlist.isNotEmpty) {
        await _pc.animateToPage(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
      await _saveRunHistory(items, limit);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveRunHistory(List<_CarouselItem> items, int? requestedCount) async {
    final db = _db;
    if (db == null || items.isEmpty) return;
    final ids = items.map((e) => e.id).toList();
    await db.insert(
      'carousel_runs',
      {
        'created_at': unixSeconds(),
        'deck': deck,
        'level': level,
        'count': requestedCount ?? items.length,
        'shuffle': shuffle ? 1 : 0,
        'item_ids': ids.join(','),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _loadHistory();
  }

  List<Widget> _buildHistoryChips() {
    if (history.isEmpty) return const [];
    return history
        .map<Widget>(
          (CarouselRun h) => InputChip(
            label: Text('${h.deck ?? '词书'} ${h.level ?? '全部'} · ${h.count ?? h.itemIds.length}条'),
            onPressed: () => _applyRun(h),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _applyRun(CarouselRun run) async {
    final db = _db;
    if (db == null) return;
    final newDeck = run.deck ?? deck;
    if (newDeck != null) {
      deck = newDeck;
      await _loadLevels(newDeck);
    }
    level = run.level ?? '全部';
    shuffle = run.shuffle;
    _countCtrl.text = run.count?.toString() ?? '';
    setState(() {});

    if (run.itemIds.isEmpty) {
      await _refreshPlaylist();
      return;
    }

    setState(() => loading = true);
    try {
      final placeholders = List.filled(run.itemIds.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id, term, reading, meaning FROM items WHERE id IN ($placeholders);',
        run.itemIds,
      );
      final map = <int, Map<String, Object?>>{};
      for (final r in rows) {
        map[(r['id'] as num).toInt()] = r;
      }
      final baseDir = appModelOf(context).baseDir;
      final items = <_CarouselItem>[];
      for (final id in run.itemIds) {
        final r = map[id];
        if (r == null) continue;
        final medias = await db.query('media', where: 'item_id=?', whereArgs: [id]);
        String? audio;
        String? image;
        for (final m in medias) {
          final type = (m['type'] as String?) ?? '';
          final raw = (m['path'] as String?)?.trim() ?? '';
          if (raw.isEmpty) continue;
          final resolved = resolveMediaPath(raw, baseDir);
          if (type == 'audio' && audio == null && File(resolved).existsSync()) {
            audio = resolved;
          } else if (type == 'image' && image == null && File(resolved).existsSync()) {
            image = resolved;
          }
        }
        items.add(
          _CarouselItem(
            id: id,
            term: (r['term'] as String?) ?? '',
            reading: (r['reading'] as String?) ?? '',
            meaning: (r['meaning'] as String?) ?? '',
            audioPath: audio,
            imagePath: image,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        playlist = items;
        currentIndex = 0;
        _announcedMissingAudio = false;
      });
      if (playlist.isNotEmpty) {
        await _pc.animateToPage(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _previewGain() async {
    if (playlist.isEmpty) return;
    final item = playlist[currentIndex];
    if (item.audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前词条没有音频可试听')));
      return;
    }
    await _player.setFilePath(item.audioPath!);
    await _player.setVolume(gain);
    await _player.setClip(start: Duration.zero, end: const Duration(seconds: 3));
    await _player.play();
    await _player.processingStateStream
        .firstWhere((s) => s == ProcessingState.completed || s == ProcessingState.idle);
    await _player.setClip(start: null, end: null);
  }

  Future<void> _playCurrentAudio({bool auto = false}) async {
    if (playlist.isEmpty) return;
    final item = playlist[currentIndex];
    if (item.audioPath == null) {
      if (!_announcedMissingAudio && mounted) {
        _announcedMissingAudio = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前列表存在缺失音频的词条，将跳过播放')));
      }
      return;
    }
    for (var i = 0; i < playTimes; i++) {
      if (auto && (!_autoLooping || _stopping)) return;
      final duration = await _player.setFilePath(item.audioPath!);
      await _player.setVolume(gain);
      await _player.play();

      if (duration != null) {
        await _player.positionStream.firstWhere((p) => p >= duration, orElse: () => Duration.zero);
      }
      await _player.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed || s.processingState == ProcessingState.idle);
      await _player.stop();

      if (auto && (!_autoLooping || _stopping)) return;
      if (i < playTimes - 1) {
        await Future.delayed(Duration(milliseconds: (repeatGapSeconds * 1000).round()));
      }
    }
  }

  void _next() {
    if (playlist.isEmpty) return;
    final next = (currentIndex + 1) % playlist.length;
    _pc.animateToPage(next, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _prev() {
    if (playlist.isEmpty) return;
    final prev = currentIndex == 0 ? playlist.length - 1 : currentIndex - 1;
    _pc.animateToPage(prev, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  Future<void> _toggleAutoPlay() async {
    if (playing) {
      setState(() {
        playing = false;
        _autoLooping = false;
        _stopping = true;
      });
      await _player.stop();
      _stopping = false;
      return;
    }
    if (playlist.isEmpty) await _refreshPlaylist();
    if (playlist.isEmpty) return;

    setState(() {
      playing = true;
      _autoLooping = true;
    });

    Future(() async {
      while (_autoLooping && mounted) {
        await _playCurrentAudio(auto: true);
        if (!_autoLooping || !mounted) break;
        await Future.delayed(Duration(milliseconds: (wordGapSeconds * 1000).round()));
        if (!_autoLooping || !mounted) break;
        final atEnd = currentIndex >= playlist.length - 1;
        if (atEnd) {
          if (!loopPlaylist) break;
          if (reshuffleOnLoop && shuffle && playlist.length > 1) {
            setState(() => playlist.shuffle());
          }
          currentIndex = 0;
          _pc.jumpToPage(0);
        } else {
          _next();
        }
        await Future.delayed(const Duration(milliseconds: 260));
      }
      if (mounted) {
        setState(() {
          playing = false;
          _autoLooping = false;
        });
      }
    });
  }

  Future<void> _setImmersive(bool enable) async {
    if (immersiveImage == enable) return;
    setState(() => immersiveImage = enable);
    if (enable) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  void _showItemMeta(_CarouselItem it) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(it.term, style: Theme.of(context).textTheme.titleLarge),
            if (it.reading.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(it.reading, style: Theme.of(context).textTheme.titleMedium),
              ),
            if (it.meaning.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(it.meaning, style: Theme.of(context).textTheme.bodyLarge),
              ),
            const SizedBox(height: 12),
            Text('词书：${deck ?? ''}  ·  级别：${level == '全部' ? '全部' : level}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);
    final ready = _db != null && m.error == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('轮换播放'),
        actions: [IconButton(onPressed: _refreshPlaylist, icon: const Icon(Icons.refresh))],
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 180,
                                    child: DropdownButtonFormField<String>(
                                      value: deck,
                                      decoration: const InputDecoration(labelText: '词书'),
                                      items: decks.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                      onChanged: (v) async {
                                        if (v == null) return;
                                        setState(() => deck = v);
                                        await _loadLevels(v);
                                        await _refreshPlaylist();
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: DropdownButtonFormField<String>(
                                      value: level,
                                      decoration: const InputDecoration(labelText: '级别'),
                                      items: levels.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                      onChanged: (v) => setState(() => level = v ?? '全部'),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 180,
                                    child: TextField(
                                      controller: _countCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: '抽取数量（留空=全部）'),
                                    ),
                                  ),
                                  FilterChip(
                                    label: const Text('打乱抽取'),
                                    selected: shuffle,
                                    onSelected: (v) => setState(() => shuffle = v),
                                  ),
                                  FilterChip(
                                    label: const Text('循环播放'),
                                    selected: loopPlaylist,
                                    onSelected: (v) => setState(() => loopPlaylist = v),
                                  ),
                                  FilterChip(
                                    label: const Text('循环时重新打乱'),
                                    selected: reshuffleOnLoop,
                                    onSelected: (v) => setState(() => reshuffleOnLoop = v),
                                  ),
                                  FilledButton.icon(
                                    onPressed: loading ? null : _refreshPlaylist,
                                    icon: const Icon(Icons.replay),
                                    label: Text(loading ? '抽取中...' : '重新抽取'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('词条间隔'),
                                      SizedBox(
                                        width: 200,
                                        child: Slider(
                                          min: 0.5,
                                          max: 8,
                                          divisions: 30,
                                          label: '${wordGapSeconds.toStringAsFixed(1)} 秒',
                                          value: wordGapSeconds,
                                          onChanged: (v) => setState(() => wordGapSeconds = double.parse(v.toStringAsFixed(1))),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('同词播放间隔'),
                                      SizedBox(
                                        width: 200,
                                        child: Slider(
                                          min: 0.3,
                                          max: 5,
                                          divisions: 24,
                                          label: '${repeatGapSeconds.toStringAsFixed(1)} 秒',
                                          value: repeatGapSeconds,
                                          onChanged: (v) => setState(() => repeatGapSeconds = double.parse(v.toStringAsFixed(1))),
                                        ),
                                      ),
                                    ],
                                  ),
                                  DropdownButton<int>(
                                    value: playTimes,
                                    items: [1, 2, 3, 4, 5]
                                        .map((v) => DropdownMenuItem(value: v, child: Text('每词播放$v次')))
                                        .toList(),
                                    onChanged: (v) => setState(() => playTimes = v ?? 1),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('音频增益'),
                                      SizedBox(
                                        width: 200,
                                        child: Slider(
                                          min: 1,
                                          max: 2.2,
                                          divisions: 12,
                                          label: '${gain.toStringAsFixed(1)}x',
                                          value: gain.clamp(1, 2.2),
                                          onChanged: (v) => setState(() => gain = double.parse(v.toStringAsFixed(1))),
                                        ),
                                      ),
                                    ],
                                  ),
                                  FilledButton.icon(
                                    onPressed: _previewGain,
                                    icon: const Icon(Icons.hearing),
                                    label: const Text('试听增益片段'),
                                  ),
                                  if (playlist.isNotEmpty)
                                    Chip(
                                      avatar: const Icon(Icons.list_alt_outlined, size: 18),
                                      label: Text('当前列表 ${playlist.length} 条'),
                                    ),
                                ],
                              ),
                              if (history.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Text('历史抽取'),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _buildHistoryChips(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: playlist.isEmpty
                              ? const Center(child: Text('先抽取一组词条，然后开始轮播'))
                              : PageView.builder(
                                  controller: _pc,
                                  onPageChanged: (i) => setState(() => currentIndex = i),
                                  itemCount: playlist.length,
                                  itemBuilder: (_, i) {
                                    final it = playlist[i];
                                    final hasImage = it.imagePath != null && File(it.imagePath!).existsSync();
                                    return DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Theme.of(context).dividerColor),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: hasImage
                                                ? InteractiveViewer(
                                                    child: Image.file(
                                                      File(it.imagePath!),
                                                      fit: BoxFit.contain,
                                                    ),
                                                  )
                                                : Container(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Theme.of(context).colorScheme.primaryContainer,
                                                          Theme.of(context).colorScheme.secondaryContainer,
                                                        ],
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(it.term,
                                                              textAlign: TextAlign.center,
                                                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                                                          if (it.reading.isNotEmpty)
                                                            Padding(
                                                              padding: const EdgeInsets.only(top: 4),
                                                              child: Text(it.reading,
                                                                  style: const TextStyle(fontSize: 20, color: Colors.black87)),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                          ),
                                          if (!immersiveImage) ...[
                                            Positioned(
                                              top: 12,
                                              left: 12,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context).colorScheme.surface.withOpacity(0.78),
                                                      borderRadius: BorderRadius.circular(14),
                                                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                                                    ),
                                                    child: Wrap(
                                                      spacing: 8,
                                                      runSpacing: 6,
                                                      children: [
                                                        Chip(
                                                          avatar: const Icon(Icons.photo, size: 18),
                                                          label: Text('第 ${i + 1}/${playlist.length} 条'),
                                                        ),
                                                        Chip(
                                                          avatar: const Icon(Icons.layers, size: 18),
                                                          label: Text(level == '全部' ? '全部级别' : '级别 $level'),
                                                        ),
                                                        if (!hasImage)
                                                          const Chip(
                                                            avatar: Icon(Icons.image_not_supported_outlined, size: 18),
                                                            label: Text('无配图，已显示文本'),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              left: 12,
                                              right: 12,
                                              bottom: 12,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.25),
                                                      borderRadius: BorderRadius.circular(14),
                                                      border: Border.all(color: Colors.white24),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        IconButton(
                                                          tooltip: '查看词条信息',
                                                          icon: const Icon(Icons.info_outline),
                                                          color: Colors.white,
                                                          onPressed: () => _showItemMeta(it),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: FilledButton.icon(
                                                            onPressed: playing ? null : () => _playCurrentAudio(),
                                                            icon: const Icon(Icons.volume_up),
                                                            label: const Text('播放当前词音频'),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        IconButton(
                                                          tooltip: '横屏仅看大图',
                                                          onPressed: () => _setImmersive(true),
                                                          icon: const Icon(Icons.fullscreen),
                                                          color: Colors.white,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ]
                                          else
                                            Positioned(
                                              top: 12,
                                              right: 12,
                                              child: FilledButton.icon(
                                                onPressed: () => _setImmersive(false),
                                                icon: const Icon(Icons.fullscreen_exit),
                                                label: const Text('退出全屏'),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        IconButton(onPressed: _prev, icon: const Icon(Icons.chevron_left)),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _toggleAutoPlay,
                            icon: Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                            label: Text(playing ? '停止轮播' : '开始轮播'),
                          ),
                        ),
                        IconButton(onPressed: _next, icon: const Icon(Icons.chevron_right)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
}

/// 为兼容历史构建脚本可能直接引用 `StateCarouselPlayerPage`
/// 的场景，这里公开一个同名状态类，继承当前实际实现，
/// 确保必需的 `build` 方法已实现，避免再出现漏实现报错。
class StateCarouselPlayerPage extends _CarouselPlayerPageState {}
