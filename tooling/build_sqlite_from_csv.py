import csv
import re
import sqlite3
from pathlib import Path

SRC = Path('data/grammar_vocab_index_all_sheets.csv')
DEST = Path('assets/jp_study_content.sqlite')

AUDIO_EXT = {'.mp3', '.wav', '.aac', '.m4a', '.ogg', '.flac'}
IMAGE_EXT = {'.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp'}


def looks_japanese(text: str) -> bool:
    return bool(re.search(r'[\u3040-\u30ff\u4e00-\u9fff]', text))


def looks_kana(text: str) -> bool:
    return bool(re.fullmatch(r'[\u3040-\u309f\u30a0-\u30ffー・\s]+', text))


def looks_path(text: str) -> bool:
    return '/' in text or '\\' in text


def looks_numeric(text: str) -> bool:
    return bool(re.fullmatch(r'[\d\s\-+*/.,]+', text))


def pick_level(cells):
    for c in cells:
        cc = c.strip().upper()
        if re.fullmatch(r'N[1-5]', cc):
            return cc
    return ''


def normalise_cell(cell: str) -> str:
    c = cell.strip()
    return c if c.lower() != 'nan' else ''


def norm_path(p: str) -> str:
    return p.replace('\\', '/')


def prepare_db(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.executescript(
        '''
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          deck TEXT NOT NULL,
          level TEXT,
          term TEXT NOT NULL,
          reading TEXT,
          meaning TEXT,
          search_text TEXT
        );
        CREATE TABLE IF NOT EXISTS media(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          path TEXT NOT NULL,
          FOREIGN KEY(item_id) REFERENCES items(id)
        );
        CREATE INDEX IF NOT EXISTS idx_items_deck_level ON items(deck, level);
        CREATE INDEX IF NOT EXISTS idx_items_term ON items(term);
        CREATE INDEX IF NOT EXISTS idx_items_search ON items(search_text);
        CREATE INDEX IF NOT EXISTS idx_media_item ON media(item_id);
        '''
    )
    conn.commit()
    return conn


def insert_row(conn: sqlite3.Connection, deck: str, level: str, term: str, reading: str, meaning: str, audio_paths, image_paths):
    search_text = ' '.join([deck, level, term, reading, meaning]).strip()
    cur = conn.cursor()
    cur.execute(
        'INSERT INTO items(deck, level, term, reading, meaning, search_text) VALUES(?,?,?,?,?,?)',
        (deck, level, term, reading, meaning, search_text),
    )
    item_id = cur.lastrowid
    for p in audio_paths:
        cur.execute('INSERT INTO media(item_id, type, path) VALUES(?,?,?)', (item_id, 'audio', p))
    for p in image_paths:
        cur.execute('INSERT INTO media(item_id, type, path) VALUES(?,?,?)', (item_id, 'image', p))


def main():
    if not SRC.exists():
        raise SystemExit(f'Missing source CSV: {SRC}')

    conn = prepare_db(DEST)
    cur = conn.cursor()
    cur.execute('DELETE FROM items;')
    cur.execute('DELETE FROM media;')
    conn.commit()

    with SRC.open(newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        total = 0
        skipped = 0
        for row in reader:
            if not row:
                continue

            deck = normalise_cell(row.get('sheet_name', '')) or '未分类'
            # 跳过 header 行或异常行
            if deck.lower() == 'sheet_name':
                continue

            raw_cells = [normalise_cell(v or '') for k, v in row.items() if k not in ('sheet_name', 'row_index')]
            cells = [c for c in raw_cells if c]
            if not cells:
                skipped += 1
                continue

            level_candidates = [row.get(k, '') for k in row if '级' in k]
            level = pick_level([c for c in level_candidates if c]) or pick_level(cells)

            term = ''
            reading = ''
            meaning_parts = []
            audio_paths = []
            image_paths = []

            for c in cells:
                lower = c.lower()
                if looks_path(c):
                    p = norm_path(c)
                    ext = Path(p).suffix.lower()
                    if ext in AUDIO_EXT:
                        audio_paths.append(p)
                    elif ext in IMAGE_EXT:
                        image_paths.append(p)
                    continue

                if not term and looks_japanese(c) and not looks_numeric(c):
                    term = c
                    continue
                if not reading and looks_kana(c):
                    reading = c
                    continue

                # 兜底：收集释义字段（排除纯数字/页码串）
                if len(meaning_parts) < 3 and len(c) <= 200 and not looks_numeric(c):
                    meaning_parts.append(c)

            if not term and cells:
                fallback = next((c for c in cells if not looks_numeric(c)), '')
                term = fallback or cells[0]

            if not term or looks_numeric(term):
                skipped += 1
                continue

            if not meaning_parts:
                meaning_parts = [c for c in cells if c not in (term, reading) and not looks_numeric(c)][:2]

            meaning = '\n'.join(dict.fromkeys([m for m in meaning_parts if m]))

            insert_row(conn, deck, level, term, reading, meaning, audio_paths, image_paths)
            total += 1
            if total % 5000 == 0:
                conn.commit()
                print(f'Inserted {total} rows...')

        conn.commit()
        print(f'Done. Inserted {total} rows, skipped {skipped}.')


if __name__ == '__main__':
    main()
