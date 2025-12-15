import csv
import datetime as dt
import hashlib
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

SRC = Path('data/grammar_vocab_index_all_sheets.csv')
DEST = Path('assets/jp_study_content.sqlite')
VERSION_FILE = Path('assets/db_version.txt')

AUDIO_EXT = {'.mp3', '.wav', '.aac', '.m4a', '.ogg', '.flac'}
IMAGE_EXT = {'.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp'}


def looks_japanese(text: str) -> bool:
    return bool(re.search(r'[\u3040-\u30ff\u4e00-\u9fff]', text))


def looks_kana(text: str) -> bool:
    return bool(re.fullmatch(r'[\u3040-\u309f\u30a0-\u30ffー・\s]+', text))


def looks_path(text: str) -> bool:
    return '/' in text or '\\' in text


def pick_level(cells: Sequence[str]):
    for c in cells:
        cc = c.strip().upper()
        if re.fullmatch(r'N[1-5]', cc):
            return cc
    return ''


def normalise_cell(cell: str) -> str:
    c = cell.strip()
    return c if c.lower() != 'nan' else ''


def is_numeric_like(text: str) -> bool:
    return bool(re.fullmatch(r'[+\-]?(\d+[\.]?\d*|\d*\.\d+)', text.strip()))


def norm_path(p: str) -> str:
    return p.replace('\\', '/')


def build_index(headers: List[str]) -> Dict[str, List[int]]:
    idx: Dict[str, List[int]] = {}
    for i, name in enumerate(headers):
        idx.setdefault(name, []).append(i)
    return idx


def find_first(row: List[str], names: Iterable[str], idx: Dict[str, List[int]]) -> str:
    for name in names:
        for i in idx.get(name, []):
            val = normalise_cell(row[i])
            if val:
                return val
    return ''


def collect_cells(
    row: List[str],
    names: Iterable[str],
    idx: Dict[str, List[int]],
    limit: int | None = None,
) -> List[str]:
    seen = []
    for name in names:
        for i in idx.get(name, []):
            val = normalise_cell(row[i])
            if val and val not in seen:
                seen.append(val)
                if limit is not None and len(seen) >= limit:
                    return seen
    return seen


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


def make_search_text(deck: str, level: str, term: str, reading: str, meaning: str) -> str:
    parts = [deck, level, term, reading]
    for seg in meaning.replace('\n', ' ').split(' '):
        seg = seg.strip()
        if seg:
            parts.append(seg)
    return ' '.join(parts).strip()


def insert_row(
    conn: sqlite3.Connection,
    deck: str,
    level: str,
    term: str,
    reading: str,
    meaning: str,
    audio_paths,
    image_paths,
):
    search_text = make_search_text(deck, level, term, reading, meaning)
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


def collect_quality_flags(term: str, reading: str, meaning: str) -> Tuple[bool, bool, bool]:
    missing_term = not term.strip()
    missing_reading = not reading.strip()
    missing_meaning = not meaning.strip()
    return missing_term, missing_reading, missing_meaning


def main():
    if not SRC.exists():
        raise SystemExit(f'Missing source CSV: {SRC}')

    conn = prepare_db(DEST)
    cur = conn.cursor()
    cur.execute('DELETE FROM items;')
    cur.execute('DELETE FROM media;')
    conn.commit()

    with SRC.open(newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        headers = next(reader)
        idx = build_index(headers)

        total = 0
        skipped = 0
        missing_term = 0
        missing_reading = 0
        missing_meaning = 0

        for row in reader:
            if not row:
                continue

            deck = find_first(row, ['sheet_name', 'deck', '分类'], idx) or normalise_cell(row[0]) or '未分类'
            cells = [normalise_cell(c) for c in row[1:] if normalise_cell(c)]
            if not cells:
                skipped += 1
                continue

            level = find_first(row, ['级别', '级别.1', 'col_40'], idx) or pick_level(cells)

            term = find_first(
                row,
                [
                    '语法点',
                    '汉字/外文',
                    '假名',
                    '副词',
                    '句型',
                    '基本句型',
                    '漢字',
                ],
                idx,
            )

            reading = find_first(row, ['假名', '读音', '音訓'], idx)

            meaning_parts = collect_cells(
                row,
                [
                    '词意',
                    '例句',
                    '例句解释',
                    '关联词',
                    '关联词解释',
                    '词汇表达能力指导',
                    '参考',
                    '备注',
                    '终了',
                    '语法点',
                ],
                idx,
                limit=6,
            )

            audio_paths = []
            image_paths = []

            for name in ['音源路径', '音源', '路径', '实际路径', '图源', '图源_2', 'col_25', 'col_26']:
                val = find_first(row, [name], idx)
                if not val:
                    continue
                p = norm_path(val)
                ext = Path(p).suffix.lower()
                if ext in AUDIO_EXT:
                    audio_paths.append(p)
                elif ext in IMAGE_EXT:
                    image_paths.append(p)

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

                if not term and looks_japanese(c):
                    term = c
                    continue
                if not reading and looks_kana(c):
                    reading = c
                    continue

                ext = Path(c).suffix.lower()
                if ext in AUDIO_EXT or ext in IMAGE_EXT:
                    continue

                if len(meaning_parts) < 6 and len(c) <= 200 and not is_numeric_like(c):
                    meaning_parts.append(c)

            if not term:
                jp_tokens = [c for c in cells if looks_japanese(c) and not looks_path(c)]
                jp_tokens.sort(key=len, reverse=True)
                term = jp_tokens[0] if jp_tokens else cells[0]

            if not meaning_parts:
                meaning_parts = [c for c in cells if c != term and not is_numeric_like(c)][:3]

            meaning = '\n'.join(dict.fromkeys([m for m in meaning_parts if m]))

            mt, mr, mm = collect_quality_flags(term, reading, meaning)
            missing_term += int(mt)
            missing_reading += int(mr)
            missing_meaning += int(mm)

            insert_row(conn, deck, level, term or '(未知)', reading, meaning, audio_paths, image_paths)
            total += 1
            if total % 5000 == 0:
                conn.commit()
                print(f'Inserted {total} rows...')

        conn.commit()
        print(f'Done. Inserted {total} rows, skipped {skipped}.')
        print(
            f'Quality summary -> missing term: {missing_term}, '
            f'missing reading: {missing_reading}, missing meaning: {missing_meaning}'
        )

    metadata = {
        'source': str(SRC),
        'rows': total,
        'generated_at': dt.datetime.utcnow().isoformat() + 'Z',
        'csv_sha256': hashlib.sha256(SRC.read_bytes()).hexdigest(),
        'missing_term': missing_term,
        'missing_reading': missing_reading,
        'missing_meaning': missing_meaning,
    }
    VERSION_FILE.write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    print(f'Version info written to {VERSION_FILE}')


if __name__ == '__main__':
    main()
