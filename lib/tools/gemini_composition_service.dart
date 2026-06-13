import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiRequestException implements Exception {
  final String message;
  GeminiRequestException(this.message);

  @override
  String toString() => 'GeminiRequestException: $message';
}

class GeminiParseException implements Exception {
  final String message;
  final String rawResponse;

  GeminiParseException(this.message, this.rawResponse);

  @override
  String toString() => 'GeminiParseException: $message';
}

@immutable
class CompositionSuggestion {
  final double idealX;
  final double idealY;
  final String patternType;
  final String detectedSubject;
  final double evOffset;
  final bool flashOn;
  final String sceneMode;

  const CompositionSuggestion({
    required this.idealX,
    required this.idealY,
    required this.patternType,
    required this.detectedSubject,
    required this.evOffset,
    required this.flashOn,
    required this.sceneMode,
  });

  factory CompositionSuggestion.fromJson(Map<String, dynamic> json) {
    return CompositionSuggestion(
      idealX: (json['idealX'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.5,
      idealY: (json['idealY'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.5,
      patternType: json['patternType'] as String? ?? 'none',
      detectedSubject: json['detectedSubject'] as String? ?? '主體',
      evOffset: (json['evOffset'] as num?)?.toDouble() ?? 0.0,
      flashOn: json['flashOn'] as bool? ?? false,
      sceneMode: json['sceneMode'] as String? ?? '一般模式',
    );
  }
}

class GeminiCompositionService {
  late final GenerativeModel _model;

  final bool hasApiKey;

  GeminiCompositionService({String modelName = 'gemini-2.5-flash-lite'})
      : hasApiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').isNotEmpty {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (!hasApiKey) {
      debugPrint('警告：找不到 GEMINI_API_KEY，請檢查 .env 檔案設定。');
    }
    _model = GenerativeModel(model: modelName, apiKey: apiKey);
  }

  static const _promptText = '''
You are a professional photo composition assistant.
Analyze the attached photo and suggest a better composition target.

Return only a valid JSON object in exactly this shape:
{
  "idealX": float,
  "idealY": float,
  "patternType": "string",
  "detectedSubject": "string",
  "evOffset": float,
  "flashOn": boolean,
  "sceneMode": "string"
}

Rules:
- idealX and idealY must be normalized coordinates from 0.0 to 1.0.
- patternType should be a short Traditional Chinese label such as "三分法", "中央構圖", or "引導線".
- detectedSubject should be a short Traditional Chinese noun phrase.
- evOffset should usually be between -2.0 and 2.0.
- flashOn should be true only when the scene clearly needs flash.
- sceneMode should be a short Traditional Chinese label.
''';

  Future<CompositionSuggestion> analyzeComposition(
    Uint8List imageBytes, {
    required double fallbackX,
    required double fallbackY,
  }) async {
    final prompt = TextPart(_promptText);
    final imagePart = DataPart('image/png', imageBytes);

    late final String responseText;
    try {
      final response = await _model.generateContent([
        Content.multi([prompt, imagePart]),
      ]);
      responseText = response.text?.trim() ?? '';
    } catch (e) {
      throw GeminiRequestException(e.toString());
    }

    try {
      final cleaned = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      final suggestion = CompositionSuggestion.fromJson(data);

      return CompositionSuggestion(
        idealX: suggestion.idealX == 0.5 && fallbackX != 0.5 ? fallbackX : suggestion.idealX,
        idealY: suggestion.idealY == 0.5 && fallbackY != 0.5 ? fallbackY : suggestion.idealY,
        patternType: suggestion.patternType,
        detectedSubject: suggestion.detectedSubject,
        evOffset: suggestion.evOffset,
        flashOn: suggestion.flashOn,
        sceneMode: suggestion.sceneMode,
      );
    } catch (e) {
      throw GeminiParseException(e.toString(), responseText);
    }
  }
}