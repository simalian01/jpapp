import csv
import json
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

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
    if path.exists():
        path.unlink()

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
          sheet TEXT,
          data_json TEXT,
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


@dataclass
class ParsedRow:
    term: str
    reading: str
    level: str
    meaning: str
    audios: list[str]
    images: list[str]
    data_json: dict


def insert_row(
    conn: sqlite3.Connection,
    *,
    deck: str,
    sheet: str,
    parsed: ParsedRow,
):
    search_text = ' '.join([deck, parsed.level, parsed.term, parsed.reading, parsed.meaning]).strip()
    cur = conn.cursor()
    cur.execute(
        'INSERT INTO items(deck, level, term, reading, meaning, sheet, data_json, search_text) VALUES(?,?,?,?,?,?,?,?)',
        (deck, parsed.level, parsed.term, parsed.reading, parsed.meaning, sheet, json.dumps(parsed.data_json, ensure_ascii=False), search_text),
    )
    item_id = cur.lastrowid
    for p in parsed.audios:
        cur.execute('INSERT INTO media(item_id, type, path) VALUES(?,?,?)', (item_id, 'audio', p))
    for p in parsed.images:
        cur.execute('INSERT INTO media(item_id, type, path) VALUES(?,?,?)', (item_id, 'image', p))


def collect_detail_fields(row: dict, *, max_items: int = 12) -> dict:
    fields = {}
    for k, v in row.items():
        if k in ('sheet_name', 'row_index'):
            continue
        val = normalise_cell(v or '')
        if not val or val in {'▶', '➸'}:
            continue
        fields[k] = val
        if len(fields) >= max_items:
            break
    return fields


def allow_sheet(name: str) -> bool:
    name = name.strip()
    return name in {'红宝书', '蓝宝书'}


def parse_red_book(row: dict) -> Optional[ParsedRow]:
    kana = normalise_cell(row.get('假名', ''))
    kanji = normalise_cell(row.get('汉字/外文', ''))
    level = normalise_cell(row.get('col_40', '')) or pick_level([row.get('级', ''), row.get('等级', '')])

    if not kana and not kanji:
        return None
    if not looks_japanese(kanji) and not looks_japanese(kana):
        return None

    audio_paths = []
    audio = normalise_cell(row.get('音源路径', ''))
    if audio:
        audio_paths.append(norm_path(audio))
    else:
        joined = ''.join(normalise_cell(row.get(k, '')) for k in ('col_28', 'col_29', 'col_30')).strip()
        if joined:
            audio_paths.append(norm_path(joined))

    image_paths = []
    img = normalise_cell(row.get('图源_2', ''))
    if not img:
        img = (normalise_cell(row.get('col_25', '')) + normalise_cell(row.get('col_26', ''))).strip()
    if img:
        image_paths.append(norm_path(img))

    term = kanji or kana
    reading = kana
    meaning = ''

    data_json = {
        '假名': kana,
        '汉字/外文': kanji,
        '等级': level,
    }
    if audio_paths:
        data_json['音源路径'] = audio_paths[0]
    if image_paths:
        data_json['图源路径'] = image_paths[0]

    return ParsedRow(
        term=term or kana,
        reading=reading,
        level=level,
        meaning=meaning,
        audios=audio_paths,
        images=image_paths,
        data_json=data_json,
    )


def main():
    if not SRC.exists():
        raise SystemExit(f'Missing source CSV: {SRC}')

    conn = prepare_db(DEST)

    with SRC.open(newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        total = 0
        skipped = 0
        for row in reader:
            if not row:
                continue

            deck = normalise_cell(row.get('sheet_name', '')) or '未分类'
            if not allow_sheet(deck):
                continue
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

            parsed = None

            if deck == '红宝书':
                parsed = parse_red_book(row)
                if parsed is None:
                    skipped += 1
                    continue

            if parsed is None:
                # 蓝宝书：兼容性解析，保留核心字段，避免引入其他 sheet 噪音
                term = normalise_cell(row.get('单词', '')) or normalise_cell(row.get('词汇', ''))
                reading = normalise_cell(row.get('假名', ''))
                meaning = normalise_cell(row.get('释义', ''))
                audio_paths = []
                image_paths = []

                for c in cells:
                    if looks_path(c):
                        p = norm_path(c)
                        ext = Path(p).suffix.lower()
                        if ext in AUDIO_EXT:
                            audio_paths.append(p)
                        elif ext in IMAGE_EXT:
                            image_paths.append(p)
                        continue

                if not term:
                    candidate = next((c for c in cells if looks_japanese(c)), '')
                    term = candidate or (cells[0] if cells else '')

                if not term or looks_numeric(term):
                    skipped += 1
                    continue

                parsed = ParsedRow(
                    term=term,
                    reading=reading,
                    level=level,
                    meaning=meaning,
                    audios=audio_paths,
                    images=image_paths,
                    data_json=collect_detail_fields(row),
                )

            insert_row(conn, deck=deck, sheet=deck, parsed=parsed)
            total += 1
            if total % 5000 == 0:
                conn.commit()
                print(f'Inserted {total} rows...')

        conn.commit()
        print(f'Done. Inserted {total} rows, skipped {skipped}.')


if __name__ == '__main__':
    main()
