import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../app_state.dart';
import '../db.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool loading = true;
  String? err;

  late Database db;

  List<DeckLevelStat> levelStats = [];
  DeckSummary overall = DeckSummary.zero();
  List<UsageRow> usages = [];
  bool showUsageDetails = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final m = appModelOf(context);
    final adb = m.db;
    if (adb == null) {
      setState(() {
        loading = false;
        err = '未导入词库';
      });
      return;
    }

    setState(() {
      loading = true;
      err = null;
    });

    db = adb;

    try {
      levelStats = await _queryLevelStats();
      overall = DeckSummary.aggregate(levelStats);
      usages = await _queryUsage();
    } catch (e) {
      err = '统计加载失败：$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<DeckLevelStat>> _queryLevelStats() async {
    final counts = await db.rawQuery('''
      SELECT deck, COALESCE(level,'未分级') AS level, COUNT(*) AS total
      FROM items
      WHERE deck IN ('红宝书','蓝宝书')
      GROUP BY deck, COALESCE(level,'未分级');
    ''');

    final marks = await db.rawQuery('''
      SELECT i.deck AS deck,
             COALESCE(i.level,'未分级') AS level,
             SUM(CASE WHEN s.reps>0 THEN 1 ELSE 0 END) AS remembered,
             SUM(CASE WHEN s.reps<0 THEN 1 ELSE 0 END) AS forgotten
      FROM items i
      LEFT JOIN srs s ON s.item_id=i.id
      WHERE i.deck IN ('红宝书','蓝宝书')
      GROUP BY i.deck, COALESCE(i.level,'未分级');
    ''');

    final markMap = {
      for (final m in marks)
        '${m['deck']}|${m['level']}': (
          remembered: (m['remembered'] as num?)?.toInt() ?? 0,
          forgotten: (m['forgotten'] as num?)?.toInt() ?? 0,
        )
    };

    return counts
        .map(
          (c) => DeckLevelStat(
            deck: (c['deck'] as String?) ?? '',
            level: (c['level'] as String?) ?? '未分级',
            total: (c['total'] as num).toInt(),
            remembered: markMap['${c['deck']}|${c['level']}']?.remembered ?? 0,
            forgotten: markMap['${c['deck']}|${c['level']}']?.forgotten ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => a.deck == b.deck ? a.level.compareTo(b.level) : a.deck.compareTo(b.deck));
  }

  Future<List<UsageRow>> _queryUsage() async {
    final rows = await db.rawQuery('''
      SELECT day, seconds, detail_opens, remembered, forgotten
      FROM usage_stats
      ORDER BY day DESC;
    ''');

    return rows
        .map((r) => UsageRow(
              day: (r['day'] as num).toInt(),
              seconds: (r['seconds'] as num?)?.toInt() ?? 0,
              detailOpens: (r['detail_opens'] as num?)?.toInt() ?? 0,
              remembered: (r['remembered'] as num?)?.toInt() ?? 0,
              forgotten: (r['forgotten'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Text('统计', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sd_storage_rounded),
            title: const Text('当前词库'),
            subtitle: Text(m.dbPath ?? '未导入'),
          ),
        ),
        const SizedBox(height: 8),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        if (err != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (!loading && err == null) ...[
          _buildTotalCard(),
          const SizedBox(height: 12),
          _buildLevelCard(),
          const SizedBox(height: 12),
          _buildUsageCard(),
        ],
      ],
    );
  }

  Widget _buildTotalCard() {
    final rememberRate = overall.total == 0 ? 0 : overall.remembered / overall.total * 100;
    final forgetRate = overall.total == 0 ? 0 : overall.forgotten / overall.total * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.leaderboard_outlined, color: Colors.indigo),
                const SizedBox(width: 6),
                Text('总览', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _pill('总词条', overall.total.toString(), color: Colors.indigo),
                _pill('记得', '${overall.remembered} / ${rememberRate.toStringAsFixed(1)}%', color: Colors.green),
                _pill('不记得', '${overall.forgotten} / ${forgetRate.toStringAsFixed(1)}%', color: Colors.orange),
              ],
            ),
            const SizedBox(height: 14),
            _bar(label: '记得占比', value: rememberRate / 100, color: Colors.green),
            const SizedBox(height: 8),
            _bar(label: '不记得占比', value: forgetRate / 100, color: Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelCard() {
    final grouped = <String, List<DeckLevelStat>>{};
    for (final s in levelStats) {
      grouped.putIfAbsent(s.deck, () => []).add(s);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text('红/蓝宝书分级', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            ...grouped.entries.map(
              (entry) {
                final deckColor = entry.key == '红宝书' ? Colors.redAccent : Colors.lightBlue;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: deckColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    ...entry.value.map(
                      (s) {
                        final rate = s.total == 0 ? 0 : s.remembered / s.total * 100;
                        final forgetRate = s.total == 0 ? 0 : s.forgotten / s.total * 100;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: deckColor.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(s.level, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  Text('总 ${s.total}'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              _bar(label: '记得 ${s.remembered}（${rate.toStringAsFixed(1)}%）', value: rate / 100, color: Colors.green),
                              const SizedBox(height: 4),
                              _bar(label: '不记得 ${s.forgotten}（${forgetRate.toStringAsFixed(1)}%）', value: forgetRate / 100, color: Colors.orange),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageCard() {
    final totalSeconds = usages.fold<int>(0, (p, e) => p + e.seconds);
    final totalDetails = usages.fold<int>(0, (p, e) => p + e.detailOpens);
    final totalRemember = usages.fold<int>(0, (p, e) => p + e.remembered);
    final totalForgotten = usages.fold<int>(0, (p, e) => p + e.forgotten);

    String formatDay(int day) {
      final dt = DateTime.utc(1970, 1, 1).add(Duration(days: day));
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    String hms(int seconds) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      final s = seconds % 60;
      if (h > 0) return '${h}h ${m}m ${s}s';
      if (m > 0) return '${m}m ${s}s';
      return '${s}s';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_outlined, color: Colors.teal),
                const SizedBox(width: 6),
                Text('使用统计', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => showUsageDetails = !showUsageDetails),
                  icon: Icon(showUsageDetails ? Icons.expand_less : Icons.expand_more),
                  label: Text(showUsageDetails ? '收起明细' : '每日明细'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _pill('累计时长', hms(totalSeconds), color: Colors.teal),
                _pill('详情次数', '$totalDetails 次', color: Colors.indigo),
                _pill('记得', '$totalRemember 次', color: Colors.green),
                _pill('不记得', '$totalForgotten 次', color: Colors.orange),
              ],
            ),
            if (showUsageDetails) ...[
              const SizedBox(height: 12),
              const Divider(),
              ...usages.map(
                (u) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.withOpacity(0.12),
                    child: Text(u.day.toString().substring(u.day.toString().length - 2)),
                  ),
                  title: Text(formatDay(u.day)),
                  subtitle: Text('${hms(u.seconds)} · 详情 ${u.detailOpens} · 记得 ${u.remembered} · 不记得 ${u.forgotten}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String title, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _bar({required String label, required double value, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${(value * 100).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class DeckLevelStat {
  final String deck;
  final String level;
  final int total;
  final int remembered;
  final int forgotten;

  DeckLevelStat({
    required this.deck,
    required this.level,
    required this.total,
    required this.remembered,
    required this.forgotten,
  });
}

class DeckSummary {
  final int total;
  final int remembered;
  final int forgotten;

  DeckSummary({required this.total, required this.remembered, required this.forgotten});

  factory DeckSummary.zero() => DeckSummary(total: 0, remembered: 0, forgotten: 0);

  factory DeckSummary.aggregate(List<DeckLevelStat> stats) {
    final t = stats.fold<int>(0, (p, e) => p + e.total);
    final r = stats.fold<int>(0, (p, e) => p + e.remembered);
    final f = stats.fold<int>(0, (p, e) => p + e.forgotten);
    return DeckSummary(total: t, remembered: r, forgotten: f);
  }
}

class UsageRow {
  final int day;
  final int seconds;
  final int detailOpens;
  final int remembered;
  final int forgotten;

  UsageRow({
    required this.day,
    required this.seconds,
    required this.detailOpens,
    required this.remembered,
    required this.forgotten,
  });
}
