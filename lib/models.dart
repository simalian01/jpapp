class VocabItem {
  final int id;
  final String deck;
  final String level;
  final String term;
  final String reading;
  final String sheet;
  final String dataJson;

  VocabItem({
    required this.id,
    required this.deck,
    required this.level,
    required this.term,
    required this.reading,
    required this.sheet,
    required this.dataJson,
  });

  static VocabItem fromMap(Map<String, Object?> m) => VocabItem(
        id: (m['id'] as num).toInt(),
        deck: (m['deck'] as String?) ?? '',
        level: (m['level'] as String?) ?? '',
        term: (m['term'] as String?) ?? '',
        reading: (m['reading'] as String?) ?? '',
        sheet: (m['sheet'] as String?) ?? '',
        dataJson: (m['data_json'] as String?) ?? '',
      );
}

class MediaRow {
  final int itemId;
  final String type; // image/audio
  final String path;

  MediaRow({required this.itemId, required this.type, required this.path});

  static MediaRow fromMap(Map<String, Object?> m) => MediaRow(
        itemId: (m['item_id'] as num).toInt(),
        type: (m['type'] as String?) ?? '',
        path: (m['path'] as String?) ?? '',
      );
}
