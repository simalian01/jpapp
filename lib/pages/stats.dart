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
        Text('统计', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('词库：${m.dbPath ?? "未导入"}'),
          ),
        ),
        const SizedBox(height: 8),
        if (loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (err != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (!loading && err == null) ...[
          _buildTotalCard(),
          const SizedBox(height: 8),
          _buildLevelCard(),
          const SizedBox(height: 8),
          _buildUsageCard(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('刷新')),
          ),
        ],
      ],
    );
  }

  Widget _buildTotalCard() {
    final rememberRate = overall.total == 0 ? 0 : overall.remembered / overall.total * 100;
    final forgetRate = overall.total == 0 ? 0 : overall.forgotten / overall.total * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('总览', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('总词条：${overall.total}'),
            Text('已标记记得：${overall.remembered}（${rememberRate.toStringAsFixed(1)}%）'),
            Text('已标记不记得：${overall.forgotten}（${forgetRate.toStringAsFixed(1)}%）'),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('红宝书 / 蓝宝书分级统计', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...levelStats.map(
              (s) {
                final rate = s.total == 0 ? 0 : s.remembered / s.total * 100;
                final forgetRate = s.total == 0 ? 0 : s.forgotten / s.total * 100;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 70, child: Text(s.deck, style: const TextStyle(fontWeight: FontWeight.w600))),
                      SizedBox(width: 80, child: Text(s.level, overflow: TextOverflow.ellipsis)),
                      Expanded(child: Text('总 ${s.total}｜记得 ${s.remembered}（${rate.toStringAsFixed(1)}%）｜不记得 ${s.forgotten}（${forgetRate.toStringAsFixed(1)}%）')),
                    ],
                  ),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('使用统计', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => showUsageDetails = !showUsageDetails),
                  icon: Icon(showUsageDetails ? Icons.expand_less : Icons.expand_more),
                  label: Text(showUsageDetails ? '收起每日明细' : '查看每日明细'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('累计使用时间：${hms(totalSeconds)}'),
            Text('累计打开详情：$totalDetails 次'),
            Text('累计标记记得：$totalRemember 次'),
            Text('累计标记不记得：$totalForgotten 次'),
            if (showUsageDetails) ...[
              const Divider(),
              ...usages.map(
                (u) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text(formatDay(u.day))),
                      Expanded(child: Text('${hms(u.seconds)}｜详情 ${u.detailOpens}｜记得 ${u.remembered}｜不记得 ${u.forgotten}')),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
