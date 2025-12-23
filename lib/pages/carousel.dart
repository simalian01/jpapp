import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../utils/media_path.dart';

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
  int takeCount = 20;
  bool shuffle = true;
  double intervalSeconds = 3;
  int playTimes = 1;

  List<_CarouselItem> playlist = [];
  bool loading = false;
  bool playing = false;
  int currentIndex = 0;
  bool _autoLooping = false;
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
    setState(() {});
    await _refreshPlaylist();
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
      final order = shuffle ? 'RANDOM()' : 'id DESC';
      final rows = await db.rawQuery(
        '''
        SELECT id, term, reading, meaning, level
        FROM items
        WHERE ${where.join(' AND ')}
        ORDER BY $order
        LIMIT ?;
        '''.
            trim(),
        [...args, takeCount],
      );
      final baseDir = appModelOf(context).baseDir;

      final items = <_CarouselItem>[];
      for (final r in rows) {
        final id = (r['id'] as num).toInt();
        final medias = await db.query('media', where: 'item_id=? AND type=?', whereArgs: [id, 'audio']);
        String? audio;
        if (medias.isNotEmpty) {
          final raw = (medias.first['path'] as String?)?.trim() ?? '';
          if (raw.isNotEmpty) {
            audio = resolveMediaPath(raw, baseDir);
            if (!File(audio).existsSync()) audio = null;
          }
        }
        items.add(
          _CarouselItem(
            id: id,
            term: (r['term'] as String?) ?? '',
            reading: (r['reading'] as String?) ?? '',
            meaning: (r['meaning'] as String?) ?? '',
            audioPath: audio,
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

  Future<void> _playCurrentAudio() async {
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
      await _player.setFilePath(item.audioPath!);
      await _player.play();
      if (i < playTimes - 1) {
        await Future.delayed(Duration(milliseconds: (intervalSeconds * 1000).round()));
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
      });
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
        await _playCurrentAudio();
        if (!_autoLooping || !mounted) break;
        await Future.delayed(Duration(milliseconds: (intervalSeconds * 1000).round()));
        if (!_autoLooping || !mounted) break;
        _next();
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
                Padding(
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
                              onChanged: (v) => setState(() => deck = v),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('抽取数量'),
                              SizedBox(
                                width: 220,
                                child: Slider(
                                  min: 5,
                                  max: 120,
                                  divisions: 23,
                                  label: '$takeCount',
                                  value: takeCount.toDouble().clamp(5, 120),
                                  onChanged: (v) => setState(() => takeCount = v.round()),
                                ),
                              ),
                            ],
                          ),
                          FilterChip(
                            label: const Text('打乱抽取'),
                            selected: shuffle,
                            onSelected: (v) => setState(() => shuffle = v),
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('间隔'),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 180,
                                child: Slider(
                                  min: 1,
                                  max: 10,
                                  divisions: 18,
                                  label: '${intervalSeconds.toStringAsFixed(1)} 秒',
                                  value: intervalSeconds,
                                  onChanged: (v) => setState(() => intervalSeconds = double.parse(v.toStringAsFixed(1))),
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
                          if (playlist.isNotEmpty)
                            Chip(
                              avatar: const Icon(Icons.list_alt_outlined, size: 18),
                              label: Text('当前列表 ${playlist.length} 条'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: playlist.isEmpty
                      ? const Center(child: Text('先抽取一组词条，然后开始轮播'))
                      : PageView.builder(
                          controller: _pc,
                          onPageChanged: (i) => setState(() => currentIndex = i),
                          itemCount: playlist.length,
                          itemBuilder: (_, i) {
                            final it = playlist[i];
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Theme.of(context).dividerColor),
                                ),
                                child: Center(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(it.term, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                                        if (it.reading.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(it.reading, style: const TextStyle(fontSize: 22)),
                                        ],
                                        if (it.meaning.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Text(it.meaning, style: const TextStyle(fontSize: 18)),
                                        ],
                                        const SizedBox(height: 16),
                                        if (it.audioPath != null)
                                          FilledButton.icon(
                                            onPressed: _playCurrentAudio,
                                            icon: const Icon(Icons.volume_up),
                                            label: const Text('播放音频'),
                                          )
                                        else
                                          const Text('无音频', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
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
}

class _CarouselItem {
  final int id;
  final String term;
  final String reading;
  final String meaning;
  final String? audioPath;

  _CarouselItem({
    required this.id,
    required this.term,
    required this.reading,
    required this.meaning,
    required this.audioPath,
  });
}
