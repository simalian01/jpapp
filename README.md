# JP Study Offline（离线背单词 App，Flutter）

这是一个**完全离线**的日语背单词 App：
- App 随包自带 sqlite 词库（由 `data/grammar_vocab_index_all_sheets.csv` 生成，涵盖红宝书、新日本语教程等全部 sheet，构建时自动生成，不再把二进制文件提交到 Git）
- 图片/音频从手机本地文件夹读取（建议：/storage/emulated/0/にほんご 及子目录）
- 仍支持导入你自己的 sqlite 词库（可选）
- 支持背诵/自测（SRS 间隔复习：SM-2 风格简化版）
- 记录每次自测结果，统计每日记住/没记住数量

## 更新说明（近期）
- 只保留红宝书/蓝宝书词书，抽取数量可手动输入（留空即全量），支持按级别筛选后再打乱抽取。
- 轮换播放侧重图片+音频，分离音频播放时长与词间间隔，增益可试听预览，支持循环/重新打乱、全屏横屏查看，并保存抽取历史。
- 应用内已去除外部 AI 依赖，保持完全离线运行体验。

> 注意：Android 设备的 SQLite 不一定支持 FTS5，所以本项目默认 **不依赖 FTS5**。
> 如词库包含 FTS5 表也没关系，App 会自动降级使用 LIKE 搜索。

---

## 你需要准备的文件
1) 你的媒体库文件夹（含图片/音频）
   - 建议放到：`内部存储/にほんご/` 下，并保持数据表中记录的相对子目录，如 `《B词汇·红宝书》/`、`《A 新日本语教程》/初级1` 等

2) （可选）自定义词库
   - 如果需要替换内置词库，可使用 `scripts/build_db.py` 或 `tooling/build_sqlite_from_csv.py` 生成 sqlite，再在【初始化】页面选择外部文件导入

---

## 生成/更新内置 sqlite
内置词库由 `data/grammar_vocab_index_all_sheets.csv` 转换而来，仓库不再提交 sqlite 二进制。更新数据后，运行：

```bash
python tooling/build_sqlite_from_csv.py
```

脚本会将 sqlite 写入 `assets/jp_study_content.sqlite`，应用启动时自动拷贝到沙盒。

---

## 手机上使用
1) 安装 APK（用 GitHub Actions 构建，见下文）
2) 首次打开 App：
   - 应用会自动准备内置词库
   - 在【初始化】或【设置】中确认媒体基准目录（默认 `/storage/emulated/0/にほんご`）
   - 点【申请所有文件访问】授予权限（便于读取本地图片/音频）

3) 去【背单词】：
   - 选择任何词库/等级（不再限定 N1~N5），模式（到期/新词/全部）、数量
   - 开始自测：点“忘记/困难/记住/秒懂”，系统自动安排下次复习

4) 去【统计】：
   - 查看今日/近30天记住率、复习数量等

---

## GitHub Actions 构建 APK（推荐）
本仓库提供 workflow：只在你手动点 Run 时构建（避免每次 push 都等很久）。
- 打开 GitHub 仓库 -> Actions -> `Build Android APK (debug)` -> Run workflow
- 构建完成后下载 Artifact：`app-debug-apk/app-debug.apk`
- Workflow 会自动运行 `tooling/build_sqlite_from_csv.py` 生成内置词库并打包到 APK

---

## 目录结构（关键）
- `lib/` Flutter 源码
- `tooling/AndroidManifest.xml` 权限（无 package=）
- `.github/workflows/build-apk.yml` Actions 构建
- `scripts/build_db.py` 从 Excel 生成 sqlite 的脚本
- `data/` 数据文件（例如生成的 `grammar_vocab_index_all_sheets.csv`、`data_manifest.json`）

---

## 代码与运行逻辑全览（文件、函数、输入/输出）
下表梳理了仓库内的所有源码/脚本文件、关键类与函数、它们的职责，以及运行时会读写的输入/输出资源，便于快速理解整体工作流。

### Flutter App（`lib/`）
- `lib/main.dart`
  - `main()`：入口；确保 Flutter 绑定初始化后，用 `AppRoot` 包裹 `JPStudyApp` 以提供全局状态。
  - `JPStudyApp`：配置 Material3 主题，设置 `HomeShell` 为首页。
- `lib/app_state.dart`
  - `AppModel extends ChangeNotifier`：全局状态与持久化（数据库路径、媒体目录、首次引导）。核心方法：
    - `init()`：读取 SharedPreferences，准备/拷贝内置 sqlite，打开数据库并校验 schema。
    - `requestAllFilesAccess()`：申请所有文件访问权限。
    - `setBaseDir()`：更新媒体基准目录并保存。
    - `logUsage()`：写入每日使用时长/详情打开/记得/不记得计数到 `usage_stats`。
    - `importDbFromPath()`：导入外部 sqlite 并重新打开。
    - `openContentDb()`：打开 sqlite，调用 `ensureUserTables()`/`ensureContentIndexes()`，校验内容表。
    - `markOnboarded()` 与 `savePrefs()`：首次引导状态的读写。
  - `AppScope`/`AppRoot`：`InheritedNotifier` 与根 StatefulWidget，提供 `appModelOf(context)` 便捷访问。
- `lib/db.dart`
  - `ensureUserTables(db)`：为用户行为数据建表（`srs`、`review_log`、`usage_stats`、`carousel_runs`），并建立索引。
  - `ensureContentIndexes(db)`：给内容库补建索引（items/media/search_text）。
  - `contentSchemaLooksValid()`：校验导入库是否包含 `items`/`media`。
  - `epochDay()`/`unixSeconds()`：日期/时间工具。
  - `sm2Update()`：简化 SM-2 算法，根据成绩返回 `SrsUpdate`（下次到期日、熟练度等）。
- `lib/models.dart`
  - `VocabItem`/`MediaRow`：基础数据模型及 `fromMap` 工厂，映射 sqlite 查询结果。
- `lib/utils/media_path.dart`
  - `buildMediaPath(baseDir, relativePath)`：将媒体基准目录与 sqlite 中的相对路径安全拼接。
- `lib/pages/home.dart`
  - `HomeShell`：底部导航容器，仅包含“记忆”和“统计”两个 Tab。
  - 生命周期：记录停留时间并通过 `AppModel.logUsage` 入库；首次启动时 `_maybeShowOnboarding()` 弹出一次性存储目录/权限说明。
- `lib/pages/library.dart`
  - `LibraryPage`：记忆列表与筛选界面。
    - 状态：`deck`/`level` 选择、查询关键词、记忆过滤（全部/记得/不记得/未标记）、是否打乱。
    - `_loadMeta()`/`_loadLevels()`：从 `items` 表读取红宝书/蓝宝书的可选层级。
    - `_queryItems()`：按筛选组合 SQL（JOIN `srs`），支持随机排序。
    - `_reload()`：重新加载结果列表。
    - `_markMemory(itemId, remember)`：调用 `sm2Update` 更新/插入 `srs`，并记录记得/不记得次数。
    - UI：顶部折叠筛选栏；列表项可直接标记记得/不记得；支持跳转详情、进入轮播播放器。
  - `ItemDetailPage`：单词详情页。
    - `_load()`：查询 `items`、`media`，按词书 sheet 展示专属字段。
    - `_playAudio()`/`_openImage()`：基于 just_audio/图片 viewer 播放或查看本地媒体。
    - 状态保留：返回列表时保持滚动位置。
  - `_ImageViewer`：全屏图片查看。
- `lib/pages/carousel.dart`
  - 模块化轮播播放器，专注图片+音频的沉浸式播放。
  - 数据结构：`_CarouselItem`（item + 媒体列表），`CarouselRun`（历史抽取记录，含 deck/level/count/shuffle/itemIds）。
  - 入口：支持从记忆列表抽取，按 deck/level 过滤、手动输入数量、随机顺序/循环/播放一次等模式，抽取结果写入 `carousel_runs`。
  - 播放：等待音频完整播放，再执行单词间隔与循环逻辑；支持音量增益预览；可切换全屏/横屏，仅显示图片并自动播放音频。
  - 历史：展示最近抽取记录，支持点击回放或重新打乱。
- `lib/pages/stats.dart`
  - `StatsPage`：统计概览。
    - `_load()`：并行获取词书分级统计与使用明细。
    - `_queryLevelStats()`：汇总 `items` + `srs`，输出 `DeckLevelStat`（每个 deck/level 的总词条数、记得/不记得计数与占比）和 `DeckSummary`（整体汇总）。
    - `_queryUsage()`：读取 `usage_stats` 日志，生成 `UsageRow` 列表（每日使用时长、详情打开次数、记得/不记得次数）。
    - UI：卡片/进度条/图标样式的概览、按日明细，以及累计汇总。
- `lib/pages/setup.dart`
  - 初始化/导入辅助页（仍可从代码引用）。
  - `_importViaPicker()`：文件选择器导入外部 sqlite。
  - `_setBaseDir()`：对话框修改媒体目录。
- `lib/pages/settings.dart`
  - 轻量占位的设置页（目前主要用于展示或扩展）。

### 数据处理与脚本
- `tooling/build_sqlite_from_csv.py`
  - 输入：`data/grammar_vocab_index_all_sheets.csv`、`data/data_manifest.json`。
  - 核心函数：
    - `load_manifest()`/`load_csv()`：读取数据与媒体清单。
    - `normalize_row()`：按 sheet 标准化字段（仅保留红宝书/蓝宝书），填充 `items` 与 `media` 需要的列。
    - `build_sqlite()`：创建 sqlite（表结构包含 `items`/`media` 及索引），写入到 `assets/jp_study_content.sqlite`。
  - 输出：`assets/jp_study_content.sqlite`（运行时会被 App 自动拷贝到沙盒）。
- `scripts/build_db.py`
  - 另一套构建脚本（依赖 `scripts/requirements.txt` 中的 Python 包），从原始 Excel 生成 `grammar_vocab_index_all_sheets.csv`。
- `tooling/AndroidManifest.xml`
  - 用于 GitHub Actions 构建时合并权限：存储读写、MANAGE_EXTERNAL_STORAGE（申请所有文件访问）。

### 数据文件与运行时输入/输出
- 输入数据：
  - `data/grammar_vocab_index_all_sheets.csv`：主词条表，字段包含 deck/level/term/reading/sheet/data_json 等。
  - `data/data_manifest.json`：媒体路径清单（供构建脚本查找图片/音频）。
  - 本地媒体目录：默认 `/storage/emulated/0/にほんご/` 下的图片与音频子目录。
- App 运行时输出/持久化：
  - `app_doc_dir/jp_study_content.sqlite`：首次启动自动拷贝的内容库（可被外部库覆盖）。
  - SQLite 用户表：`srs`（记忆状态）、`review_log`（历史评分）、`usage_stats`（每日使用）、`carousel_runs`（轮播抽取记录）。
  - SharedPreferences：`content_db_path`、`media_base_dir`、`onboarded_once` 用于记忆导入路径/媒体目录/是否展示过首次引导。

### 运行流程速览
1. **首次启动**：`AppModel.init()` 读取偏好设置并拷贝内置 sqlite，`HomeShell` 弹出一次性权限/目录说明。
2. **记忆列表**：`LibraryPage` 加载红宝书/蓝宝书层级 -> `_queryItems()` 拉取词条 -> 列表中可直接标记记得/不记得，或进入 `ItemDetailPage` 查看图片/音频/字段。
3. **轮播**：在列表中选择数量、级别、是否打乱/循环，生成 `CarouselRun` 并写入 `carousel_runs`；`CarouselPlayerPage` 逐条显示图片并播放音频，按音频结束 + 词间间隔控制节奏。
4. **统计**：`StatsPage` 读取 `items`+`srs` 与 `usage_stats`，展示词书分级分布、记得/不记得比例，以及每日使用明细和累计数据。
5. **数据导入/媒体目录**：如需手动导入词库或修改媒体路径，可调用 `SetupPage` 的导入与目录设置功能；`AppModel` 会刷新数据库连接并保存偏好。

