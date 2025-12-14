import argparse
import sqlite3
import pandas as pd
import re
from pathlib import Path

MARKER = r"\にほんご"
MARKER2 = r"/にほんご/"

def norm_path(p: str) -> str:
    if p is None:
        return ""
    p = str(p).strip()
    if not p or p.lower() == "nan":
        return ""
    return p.replace("\\", "/")

def make_search_text(*parts) -> str:
    s = " ".join([str(x) for x in parts if x is not None and str(x).strip() and str(x).lower() != "nan"])
    s = re.sub(r"\s+", " ", s).strip()
    return s

def create_schema(conn: sqlite3.Connection):
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      deck TEXT NOT NULL,
      level TEXT,
      term TEXT NOT NULL,
      reading TEXT,
      meaning TEXT,
      search_text TEXT
    );
    """)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS media(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL,
      type TEXT NOT NULL,   -- 'audio' | 'image'
      path TEXT NOT NULL,
      FOREIGN KEY(item_id) REFERENCES items(id)
    );
    """)
    # SRS tables (app uses these)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS srs(
      item_id INTEGER PRIMARY KEY,
      reps INTEGER NOT NULL DEFAULT 0,
      interval_days INTEGER NOT NULL DEFAULT 0,
      due_day INTEGER NOT NULL DEFAULT 0,
      ease REAL NOT NULL DEFAULT 2.5,
      last_day INTEGER NOT NULL DEFAULT 0
    );
    """)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS reviews(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      day INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      rating TEXT NOT NULL
    );
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_items_deck ON items(deck);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_items_level ON items(level);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_items_search_text ON items(search_text);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_media_item ON media(item_id);")
    conn.commit()

def insert_item(conn, deck, term, level="", reading="", meaning="", audio="", image=""):
    term = "" if term is None else str(term).strip()
    if not term or term.lower() == "nan":
        return None
    deck = str(deck).strip()
    level = "" if level is None else str(level).strip()
    reading = "" if reading is None else str(reading).strip()
    meaning = "" if meaning is None else str(meaning).strip()

    search_text = make_search_text(deck, level, term, reading, meaning)

    cur = conn.cursor()
    cur.execute(
        "INSERT INTO items(deck, level, term, reading, meaning, search_text) VALUES(?,?,?,?,?,?)",
        (deck, level, term, reading, meaning, search_text),
    )
    item_id = cur.lastrowid

    if audio:
        ap = norm_path(audio)
        if ap:
            cur.execute("INSERT INTO media(item_id, type, path) VALUES(?,?,?)", (item_id, "audio", ap))
    if image:
        ip = norm_path(image)
        if ip:
            cur.execute("INSERT INTO media(item_id, type, path) VALUES(?,?,?)", (item_id, "image", ip))

    return item_id

def handle_red_book(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="红宝书")
    # 核心列（你这个 4.2 版本里验证过）
    col_kana = "假名"
    col_kanji = "汉字/外文"
    col_level = "Unnamed: 39"      # N1..N5
    col_audio = "音源路径"
    col_image = "图源.1"

    for _, r in df.iterrows():
        kana = r.get(col_kana, "")
        kanji = r.get(col_kanji, "")
        term = kanji if str(kanji).strip() and str(kanji).lower() != "nan" else kana
        reading = kana
        level = r.get(col_level, "")
        audio = r.get(col_audio, "")
        image = r.get(col_image, "")
        insert_item(conn, "红宝书", term=term, level=level, reading=reading, meaning="", audio=audio, image=image)

def handle_sheet1_adverbs(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="Sheet1")
    # 序号, 副词, 词意, 例句...
    for _, r in df.iterrows():
        term = r.get("副词", "")
        meaning = r.get("词意", "")
        example = r.get("例句", "")
        ex_mean = r.get("例句解释", "")
        insert_item(conn, "副词（Sheet1）", term=term, level="", reading="", meaning=make_search_text(meaning, example, ex_mean))

def handle_exam_countermeasure(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="考前对策")
    for _, r in df.iterrows():
        term = r.get("句型", "")
        level = r.get("级别", "")
        # 优先实际路径
        img = r.get("实际路径", "") or r.get("路径", "")
        page = r.get("页数", "")
        meaning = f"页码：{page}" if str(page).strip() and str(page).lower() != "nan" else ""
        insert_item(conn, "考前对策", term=term, level=level, reading="", meaning=meaning, image=img)

def handle_shinkanzen(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="新完全掌握")
    # 句型 + 路径
    for _, r in df.iterrows():
        term = r.get("句型", "")
        img = r.get("路径", "")
        p = r.get("页码", "")
        meaning = f"页码：{p}" if str(p).strip() and str(p).lower() != "nan" else ""
        insert_item(conn, "新完全掌握", term=term, meaning=meaning, image=img)

def handle_donnatoki(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="どんな时どう使う")
    for _, r in df.iterrows():
        term = r.get("句型", "")
        ref = r.get("参考", "")
        page = r.get("页码", "")
        meaning = make_search_text(f"参考：{ref}", f"页码：{page}")
        insert_item(conn, "どんな时どう使う", term=term, meaning=meaning)

def handle_new_textbook(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="新日本语教程")
    # 这里分两类：图片索引 + 基本句型/词汇指导
    for _, r in df.iterrows():
        img = r.get("实际路径", "") or r.get("路径", "")
        lesson = r.get("初1", "")  # 课号
        pattern = r.get("基本句型", "")
        vocabguide = r.get("词汇表达能力指导", "")

        if img and str(img).strip().lower() != "nan":
            term = f"初级1 第{lesson}课 图片"
            insert_item(conn, "新日本语教程-图片", term=term, meaning="", image=img)

        if pattern and str(pattern).strip().lower() != "nan":
            insert_item(conn, "新日本语教程-基本句型", term=str(pattern).strip(), meaning=str(vocabguide).strip())

def handle_diff(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="疑难辨析")
    # 这张表列名很乱：我们只要把“对比点 + 两个表达 + 图片路径”收进去
    # 找到第一个包含 F:\...\にほんご 的列作为实际路径
    path_col = None
    for c in df.columns:
        s = df[c].astype(str)
        if s.str.contains(r"\\にほんご\\", na=False).any():
            path_col = c
            break

    for _, r in df.iterrows():
        topic = r.get("终了", "")  # 例如：终了/替换/...
        a1 = make_search_text(r.get("~", ""), r.get("がおわる", ""))
        a2 = make_search_text(r.get("~.1", ""), r.get("をおわる", ""))
        term = make_search_text(topic, f"{a1} vs {a2}")
        img = r.get(path_col, "") if path_col is not None else ""
        insert_item(conn, "疑难辨析", term=term, meaning="", image=img)

def handle_vocab_diff(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="词汇辨析")
    # 找到实际路径列
    path_col = None
    for c in df.columns:
        s = df[c].astype(str)
        if s.str.contains(r"\\にほんご\\", na=False).any():
            path_col = c
            break
    # term 列：这张表第三列就是条目文本（书名那列）
    text_col = df.columns[2]

    for _, r in df.iterrows():
        term = r.get(text_col, "")
        img = r.get(path_col, "") if path_col is not None else ""
        insert_item(conn, "词汇辨析", term=term, meaning="", image=img)

def handle_grammar_newthinking(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="日语语法新思维")
    for _, r in df.iterrows():
        term = r.get("语法点", "") or r.get("順\n序", "")
        page = r.get("页码", "")
        insert_item(conn, "日语语法新思维", term=term, meaning=make_search_text("页码：", page))

def handle_jpxy_dict(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="《日本语句型辞典》")
    # 实际路径列：包含 にほんご
    path_col = None
    for c in df.columns:
        s = df[c].astype(str)
        if s.str.contains(r"\\にほんご\\", na=False).any():
            path_col = c
            break
    # term 列通常是最后一列（例如 あか/あさ/…）
    term_col = df.columns[-1]

    for _, r in df.iterrows():
        term = r.get(term_col, "")
        img = r.get(path_col, "") if path_col is not None else ""
        insert_item(conn, "日本语句型辞典", term=term, meaning="", image=img)

def handle_blue_book(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="蓝宝书")
    # 没有路径，作为目录索引
    for _, r in df.iterrows():
        t2015 = r.get("句型・2015年版目录", "")
        lv2015 = r.get("级别.1", "")
        p2015 = r.get("页数.2", "")
        if str(t2015).strip() and str(t2015).lower() != "nan":
            insert_item(conn, "蓝宝书-目录", term=t2015, level=lv2015, meaning=make_search_text("页码：", p2015))

def handle_kanji(conn, xls: Path):
    df = pd.read_excel(xls, sheet_name="日语汉字")
    # 只保留“漢字、音訓”两列
    if "漢字" in df.columns and "音訓" in df.columns:
        for _, r in df.iterrows():
            k = r.get("漢字", "")
            onkun = r.get("音訓", "")
            if str(k).strip() and str(k).lower() != "nan":
                insert_item(conn, "日语汉字", term=k, meaning=str(onkun).strip())

def handle_toc(conn, xls: Path, sheet: str):
    df = pd.read_excel(xls, sheet_name=sheet)
    # 纯目录（顾明耀/皮细庚/变形与活用等）——把第一列/第二列拼成 term
    for _, r in df.iterrows():
        parts = []
        for c in df.columns[:6]:
            v = r.get(c, "")
            if str(v).strip() and str(v).lower() != "nan":
                parts.append(str(v).strip())
        term = " ".join(parts)
        if term:
            insert_item(conn, sheet, term=term, meaning="")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--excel", required=True, help="输入 Excel 路径")
    ap.add_argument("--out", required=True, help="输出 sqlite 路径，例如 jp_study_content.sqlite")
    args = ap.parse_args()

    xls = Path(args.excel)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()

    conn = sqlite3.connect(out)
    create_schema(conn)

    # 逐个 sheet 导入（一次性）
    handle_red_book(conn, xls)
    handle_sheet1_adverbs(conn, xls)
    handle_exam_countermeasure(conn, xls)
    handle_shinkanzen(conn, xls)
    handle_donnatoki(conn, xls)
    handle_new_textbook(conn, xls)
    handle_diff(conn, xls)
    handle_vocab_diff(conn, xls)
    handle_grammar_newthinking(conn, xls)
    handle_jpxy_dict(conn, xls)
    handle_blue_book(conn, xls)
    handle_kanji(conn, xls)

    # 这些是目录类，尽量也收进去
    for sheet in ["顾明耀", "皮细庚", "变形与活用", "词典存放目录"]:
        try:
            handle_toc(conn, xls, sheet)
        except Exception:
            pass

    conn.commit()
    conn.close()
    print(f"OK -> {out}")

if __name__ == "__main__":
    main()
