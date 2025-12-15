# JP Study Offline（离线背单词 App，Flutter）

这是一个**完全离线**的日语背单词 App：
- App 随包自带 sqlite 词库（由 `data/grammar_vocab_index_all_sheets.csv` 生成，涵盖红宝书、新日本语教程等全部 sheet，构建时自动生成，不再把二进制文件提交到 Git）
- 图片/音频从手机本地文件夹读取（建议：/storage/emulated/0/にほんご 及子目录）
- 仍支持导入你自己的 sqlite 词库（可选）
- 支持背诵/自测（SRS 间隔复习：SM-2 风格简化版）
- 记录每次自测结果，统计每日记住/没记住数量

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

脚本会将 sqlite 写入 `assets/jp_study_content.sqlite`，并生成 `assets/db_version.txt`（包含 CSV 的 hash/行数）。
应用启动时会对比该版本号自动刷新内置词库到沙盒，避免升级后仍使用旧数据。

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

## 协作与合并
- `.gitattributes` 已声明 CSV/JSON/Dart 等为文本文件、数据库/APK 视为二进制，并对核心工程与生成物设定了固定策略：
  - `assets/jp_study_content.sqlite`、`assets/db_version.txt`、主要页面（如 `lib/main.dart`、`lib/pages/*`）、`pubspec.yaml`、`README.md` 等在合并时默认保留当前分支，避免网页端提示“必须先解决冲突”。
  - 若需吸收对方的实现，可在本地拉取后对相关文件 cherry-pick 或手工合并，再重新生成词库资产。
- 遇到冲突时建议流程：
  1. `git checkout --ours assets/jp_study_content.sqlite assets/db_version.txt`（保留当前分支的生成产物）
  2. 解决其余文本冲突（如 README、Dart 代码），确保 `data/grammar_vocab_index_all_sheets.csv` 选取最新版本。
  3. 运行 `python tooling/build_sqlite_from_csv.py` 重新生成 sqlite + 版本文件，再 `git add .`。
  4. `git rebase --continue` 或 `git merge --continue` 完成合并。

