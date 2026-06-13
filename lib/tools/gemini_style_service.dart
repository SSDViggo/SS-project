import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiStyleRequestException implements Exception {
  final String message;
  GeminiStyleRequestException(this.message);

  @override
  String toString() => 'GeminiStyleRequestException: $message';
}

class GeminiStyleParseException implements Exception {
  final String message;
  final String rawResponse;
  GeminiStyleParseException(this.message, this.rawResponse);

  @override
  String toString() => 'GeminiStyleParseException: $message';
}

/// 單一風格選項：給Unsplash搜尋用的英文關鍵詞 + 給使用者看的中文標籤
@immutable
class StyleOption {
  final String searchQuery;
  final String label;

  const StyleOption({required this.searchQuery, required this.label});

  factory StyleOption.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const StyleOption(searchQuery: 'photography', label: '風格');
    }
    return StyleOption(
      searchQuery: json['searchQuery'] as String? ?? 'photography',
      label: json['label'] as String? ?? '風格',
    );
  }
}

/// 這個service負責agentic流程裡的**Reasoning**步驟：
/// 看一張照片，自主判斷「適合這張照片的3種不同調色/風格方向」，
/// 並把每種方向轉換成適合拿去Unsplash搜尋的英文關鍵詞。
///
/// 回傳的是「決策」（關鍵詞+標籤），不是圖片本身——
/// 實際搜圖由[UnsplashService]（工具）執行。
class GeminiStyleService {
  late final GenerativeModel _model;
  final bool hasApiKey;

  GeminiStyleService({String modelName = 'gemini-2.5-flash-lite'})
      : hasApiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').isNotEmpty {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (!hasApiKey) {
      debugPrint('警告：找不到 GEMINI_API_KEY，請檢查 .env 檔案設定。');
    }
    _model = GenerativeModel(model: modelName, apiKey: apiKey);
  }

  static const _promptText = '''
You are a professional photo color-grading assistant.

Look at the attached photo and suggest THREE distinctly DIFFERENT
color-grading / mood styles that could work well for this kind of photo
(e.g. warm cinematic, moody dark & contrasty, bright airy minimal,
vintage film, vibrant saturated, cool blue tone, etc).

The three styles MUST be meaningfully different from each other,
so a user could compare them side by side.

For each style, provide:
- "searchQuery": a short English phrase (3-6 words) suitable for searching
  a stock photo site (Unsplash) to find a REFERENCE PHOTO showcasing that
  mood/style. Include the general subject type from the original photo
  (e.g. "food", "portrait", "landscape") so the reference photo is relevant.
- "label": a short label in Traditional Chinese (繁體中文, max 8 characters)
  describing the style for a user to read, e.g. "溫暖電影感".

You MUST respond ONLY with a valid JSON object in exactly this shape:
{
  "styles": [
    {"searchQuery": "...", "label": "..."},
    {"searchQuery": "...", "label": "..."},
    {"searchQuery": "...", "label": "..."}
  ]
}

Do not include any image data or pixel values in your response.
''';

  /// 分析照片，回傳3組不同風格的(搜尋關鍵詞, 中文標籤)。
  Future<List<StyleOption>> suggestStyles(Uint8List imageBytes) async {
    final prompt = TextPart(_promptText);
    final imagePart = DataPart('image/jpeg', imageBytes);

    late final String responseText;
    try {
      final response = await _model.generateContent([
        Content.multi([prompt, imagePart]),
      ]);
      responseText = response.text?.trim() ?? '';
    } catch (e) {
      throw GeminiStyleRequestException(e.toString());
    }

    try {
      final cleaned = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      final styles = data['styles'] as List<dynamic>?;
      if (styles == null || styles.isEmpty) {
        throw GeminiStyleParseException('回應中沒有styles陣列', responseText);
      }
      return styles.map(StyleOption.fromJson).toList();
    } catch (e) {
      if (e is GeminiStyleParseException) rethrow;
      throw GeminiStyleParseException(e.toString(), responseText);
    }
  }
}