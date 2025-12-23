import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';

const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

class FuriganaSentence {
  final String original;
  final String annotated;
  final String translation;

  FuriganaSentence({required this.original, required this.annotated, required this.translation});

  factory FuriganaSentence.fromMap(Map<String, dynamic> map) {
    return FuriganaSentence(
      original: '${map['original'] ?? ''}',
      annotated: '${map['annotated'] ?? ''}',
      translation: '${map['translation'] ?? ''}',
    );
  }

  Map<String, String> toMap() => {
        'original': original,
        'annotated': annotated,
        'translation': translation,
      };
}

class OcrResult {
  final String rawText;
  final List<FuriganaSentence> sentences;

  OcrResult({required this.rawText, required this.sentences});
}

class GeminiClient {
  GeminiClient();

  bool get enabled => _geminiApiKey.isNotEmpty;

  GenerativeModel _ocrModel() => GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _geminiApiKey,
      );

  Future<OcrResult> extractImageText(File image) async {
    if (!enabled) {
      throw Exception('未配置 GEMINI_API_KEY 环境变量，无法调用 AI。');
    }
    if (!await image.exists()) {
      throw Exception('图片不存在：${image.path}');
    }

    final bytes = await image.readAsBytes();
    final mime = lookupMimeType(image.path) ?? 'image/jpeg';
    final prompt = '''
以下の画像に含まれる日本語のテキストを抽出してください。出力形式は JSON 配列とし、各要素は以下のキーを持つオブジェクトです：
1. "original": 元の日本語の文。
2. "annotated": すべての漢字の直後に（）で平仮名の振り仮名を付けた文（例： 漢字(かんじ) ）。
3. "translation": 中国語訳。
JSON 以外の出力は不要です。
''';

    final response = await _ocrModel().generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart(mime, bytes),
      ]),
    ]);

    final raw = response.text?.trim();
    if (raw == null || raw.isEmpty) {
      throw Exception('AI 没有返回内容');
    }

    List<dynamic> parsed;
    try {
      parsed = jsonDecode(raw) as List<dynamic>;
    } catch (e) {
      throw Exception('解析 AI 返回失败：$e\n$raw');
    }

    final sentences = parsed
        .whereType<Map<String, dynamic>>()
        .map(FuriganaSentence.fromMap)
        .toList();
    final merged = sentences.map((s) => s.original).join('\n');

    return OcrResult(rawText: merged, sentences: sentences);
  }
}

final geminiClient = GeminiClient();
