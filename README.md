# JP Study Offline（离线背单词 App，Flutter）

这是一个**完全离线**的日语背单词 App：
- 词库来自你提供的 Excel（重点支持「红宝书」sheet，按 N1~N5 分级）
- 图片/音频从手机本地文件夹读取（建议：/storage/emulated/0/にほんご）
- 支持导入 sqlite 词库
- 支持背诵/自测（SRS 间隔复习：SM-2 风格简化版）
- 记录每次自测结果，统计每日记住/没记住数量

> 注意：Android 设备的 SQLite 不一定支持 FTS5，所以本项目默认 **不依赖 FTS5**。
> 如词库包含 FTS5 表也没关系，App 会自动降级使用 LIKE 搜索。

---

## 你需要准备的文件
1) 你的媒体库文件夹（含图片/音频）  
   建议放到：`内部存储/にほんご/ ...`（保持原目录结构）

2) 词库 sqlite（推荐用脚本从 Excel 生成，避免不兼容）
   - 用本仓库的 `scripts/build_db.py` 生成：`jp_study_content.sqlite`
   - 放到手机：`内部存储/Download/jp_study_content.sqlite`

---

## 生成 sqlite（Windows 最快方式）
1) 安装 Python 3.10+  
2) 打开命令行，进入本仓库 `scripts/` 目录  
3) 安装依赖：
```bash
pip install -r requirements.txt
```
4) 生成数据库（把路径改成你的 Excel）：
```bash
python build_db.py --excel "文法词汇知识点索引4.2_win系统版.xlsx" --out "jp_study_content.sqlite"
```

> 脚本会重点抽取：红宝书的「假名」「汉字/外文」「音源路径」「图源」并自动从音频文件名中提取 N1~N5。

---

## 手机上使用
1) 安装 APK（用 GitHub Actions 构建，见下文）  
2) 首次打开 App：
   - 点【导入词库 sqlite】导入 `jp_study_content.sqlite`
   - 右上角文件夹图标可设置媒体基准目录（默认 `/storage/emulated/0/にほんご`）
   - 点【申请所有文件访问】授予权限（非上架版本，便于读取大文件夹）

3) 去【背单词】：
   - 选择：红宝书、N1~N5、模式（到期/新词/全部）、数量
   - 开始自测：点“忘记/困难/记住/秒懂”，系统自动安排下次复习

4) 去【统计】：
   - 查看今日/近30天记住率、复习数量等

---

## GitHub Actions 构建 APK（推荐）
本仓库提供 workflow：只在你手动点 Run 时构建（避免每次 push 都等很久）。
- 打开 GitHub 仓库 -> Actions -> `Build Android APK (debug)` -> Run workflow
- 构建完成后下载 Artifact：`app-debug-apk/app-debug.apk`

---

## 目录结构（关键）
- `lib/` Flutter 源码
- `tooling/AndroidManifest.xml` 权限（无 package=）
- `.github/workflows/build-apk.yml` Actions 构建
- `scripts/build_db.py` 从 Excel 生成 sqlite 的脚本

