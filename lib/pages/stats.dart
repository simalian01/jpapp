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
  List<DayStat> days = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final m = appModelOf(context);
    final db = m.db;
    if (db == null) {
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

    try {
      final today = epochDay(DateTime.now());
      final from = today - 29;

      final rows = await db.rawQuery('''
        SELECT day,
               SUM(CASE WHEN grade>=3 THEN 1 ELSE 0 END) AS remembered,
               SUM(CASE WHEN grade<=1 THEN 1 ELSE 0 END) AS forgotten,
               COUNT(*) AS total
        FROM review_log
        WHERE day BETWEEN ? AND ?
        GROUP BY day
        ORDER BY day DESC;
      ''', [from, today]);

      final map = {for (var r in rows) (r['day'] as num).toInt(): DayStat.fromMap(r)};

      days = List.generate(30, (i) {
        final d = today - i;
        return map[d] ?? DayStat(day: d, remembered: 0, forgotten: 0, total: 0);
      });
    } catch (e) {
      err = '统计加载失败：$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = appModelOf(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('统计', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('词库：${m.dbPath ?? "未导入"}'),
          ),
        ),
        const SizedBox(height: 8),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (err != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (!loading && err == null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _todaySummary(days.isEmpty ? null : days.first),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('近 30 天', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...days.map((d) => _dayRow(d)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('刷新')),
        ],
      ],
    );
  }

  Widget _todaySummary(DayStat? d) {
    if (d == null) return const Text('暂无数据');
    final rate = d.total == 0 ? 0.0 : (d.remembered / d.total * 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('今日', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('复习：${d.total}'),
        Text('记住：${d.remembered}'),
        Text('忘记：${d.forgotten}'),
        Text('记住率：${rate.toStringAsFixed(1)}%'),
      ],
    );
  }

  Widget _dayRow(DayStat d) {
    final dt = DateTime.utc(1970, 1, 1).add(Duration(days: d.day));
    final label = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final rate = d.total == 0 ? 0.0 : (d.remembered / d.total * 100.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: Text('复习 ${d.total}｜记住 ${d.remembered}｜忘记 ${d.forgotten}｜${rate.toStringAsFixed(0)}%'),
          ),
        ],
      ),
    );
  }
}

class DayStat {
  final int day;
  final int remembered;
  final int forgotten;
  final int total;

  DayStat({required this.day, required this.remembered, required this.forgotten, required this.total});

  static DayStat fromMap(Map<String, Object?> m) => DayStat(
        day: (m['day'] as num).toInt(),
        remembered: (m['remembered'] as num?)?.toInt() ?? 0,
        forgotten: (m['forgotten'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
      );
}
