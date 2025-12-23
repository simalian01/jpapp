import 'package:sqflite/sqflite.dart';

/// 用户进度（SRS）表：独立于内容表，导入任何内容库都能用
Future<void> ensureUserTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS srs(
      item_id INTEGER PRIMARY KEY,
      deck TEXT,
      level TEXT,
      state INTEGER NOT NULL DEFAULT 0,          -- 0=new 1=learning 2=review
      ease REAL NOT NULL DEFAULT 2.5,
      interval_days INTEGER NOT NULL DEFAULT 0,
      due_day INTEGER NOT NULL DEFAULT 0,        -- days since epoch
      reps INTEGER NOT NULL DEFAULT 0,
      lapses INTEGER NOT NULL DEFAULT 0,
      last_review_day INTEGER NOT NULL DEFAULT 0
    );
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS review_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL,
      day INTEGER NOT NULL,                      -- days since epoch
      grade INTEGER NOT NULL,                    -- 1 again,2 hard,3 good,4 easy
      ts INTEGER NOT NULL                         -- unix seconds
    );
  ''');

  await db.execute('CREATE INDEX IF NOT EXISTS idx_log_day ON review_log(day);');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_srs_due ON srs(due_day);');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_srs_deck_level ON srs(deck, level);');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS usage_stats(
      day INTEGER PRIMARY KEY,                   -- days since epoch
      seconds INTEGER NOT NULL DEFAULT 0,        -- 累计使用时长（秒）
      detail_opens INTEGER NOT NULL DEFAULT 0,   -- 打开详情页次数
      remembered INTEGER NOT NULL DEFAULT 0,     -- 标记“记得”
      forgotten INTEGER NOT NULL DEFAULT 0       -- 标记“不记得”
    );
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS ocr_cache(
      item_id INTEGER PRIMARY KEY,
      image_path TEXT,
      raw_text TEXT,
      sentences_json TEXT,
      updated_at INTEGER
    );
  ''');
}

/// ✅ 内容索引：保证新词/搜索/筛选不卡（即使库里原本没建索引）
Future<void> ensureContentIndexes(Database db) async {
  // items(deck,level) 用于筛选
  await db.execute('CREATE INDEX IF NOT EXISTS idx_items_deck_level ON items(deck, level);');
  // items(term) 用于浏览/排序/简单查询
  await db.execute('CREATE INDEX IF NOT EXISTS idx_items_term ON items(term);');
  // search_text 用于 LIKE 搜索（非常关键）
  await db.execute('CREATE INDEX IF NOT EXISTS idx_items_search_text ON items(search_text);');
  // media(item_id) 用于取音频/图片
  await db.execute('CREATE INDEX IF NOT EXISTS idx_media_item ON media(item_id);');
}

/// 判断导入的内容库是否符合本 App 的最小 schema（items/media）
Future<bool> contentSchemaLooksValid(Database db) async {
  final t = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('items','media');",
  );
  final names = t.map((e) => e['name'] as String).toSet();
  return names.contains('items') && names.contains('media');
}

/// days since epoch (UTC)
int epochDay(DateTime dt) {
  final u = dt.toUtc();
  final d = DateTime.utc(u.year, u.month, u.day);
  return d.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// unix seconds
int unixSeconds() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

/// 简化版 SM-2：根据 grade 更新（以“天”为单位）
SrsUpdate sm2Update({
  required int today,
  required double ease,
  required int intervalDays,
  required int reps,
  required int lapses,
  required int grade, // 1..4
}) {
  var e = ease;
  var interval = intervalDays;
  var r = reps;
  var l = lapses;

  if (grade <= 1) {
    l += 1;
    r = 0;
    interval = 0;
  } else {
    r += 1;
    final q = grade + 1; // 2..5
    e = e + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (e < 1.3) e = 1.3;

    if (r == 1) {
      interval = 1;
    } else if (r == 2) {
      interval = 3;
    } else {
      final mult = grade == 2 ? 1.2 : (grade == 3 ? e : e * 1.3);
      interval = (interval * mult).round();
      if (interval < 1) interval = 1;
    }
  }

  final due = today + interval;
  final state = grade <= 1 ? 1 : 2;

  return SrsUpdate(
    ease: e,
    intervalDays: interval,
    reps: r,
    lapses: l,
    dueDay: due,
    state: state,
  );
}

class SrsUpdate {
  final double ease;
  final int intervalDays;
  final int reps;
  final int lapses;
  final int dueDay;
  final int state;

  SrsUpdate({
    required this.ease,
    required this.intervalDays,
    required this.reps,
    required this.lapses,
    required this.dueDay,
    required this.state,
  });
}
