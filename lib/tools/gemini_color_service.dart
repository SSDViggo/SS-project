import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiColorRequestException implements Exception {
  final String message;
  GeminiColorRequestException(this.message);

  @override
  String toString() => 'GeminiColorRequestException: $message';
}

class GeminiColorParseException implements Exception {
  final String message;
  final String rawResponse;
  GeminiColorParseException(this.message, this.rawResponse);

  @override
  String toString() => 'GeminiColorParseException: $message';
}

@immutable
class ColorAdjustmentItem {
  final double value;

  final String reason;

  const ColorAdjustmentItem({required this.value, required this.reason});

  factory ColorAdjustmentItem.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const ColorAdjustmentItem(value: 0, reason: '暫無建議');
    }
    return ColorAdjustmentItem(
      value: (json['value'] as num?)?.toDouble().clamp(-100, 100) ?? 0.0,
      reason: json['reason'] as String? ?? '暫無建議',
    );
  }
}

@immutable
class ColorAdjustmentSuggestion {
  final ColorAdjustmentItem brightness;
  final ColorAdjustmentItem saturation;
  final ColorAdjustmentItem contrast;
  final ColorAdjustmentItem sharpness;

  const ColorAdjustmentSuggestion({
    required this.brightness,
    required this.saturation,
    required this.contrast,
    required this.sharpness,
  });

  factory ColorAdjustmentSuggestion.fromJson(Map<String, dynamic> json) {
    return ColorAdjustmentSuggestion(
      brightness: ColorAdjustmentItem.fromJson(json['brightness']),
      saturation: ColorAdjustmentItem.fromJson(json['saturation']),
      contrast: ColorAdjustmentItem.fromJson(json['contrast']),
      sharpness: ColorAdjustmentItem.fromJson(json['sharpness']),
    );
  }
}

class GeminiColorService {
  late final GenerativeModel _model;

  final bool hasApiKey;

  GeminiColorService({String modelName = 'gemini-2.5-flash-lite'})
      : hasApiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').isNotEmpty {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (!hasApiKey) {
      debugPrint('警告：找不到 GEMINI_API_KEY，請檢查 .env 檔案設定。');
    }
    _model = GenerativeModel(model: modelName, apiKey: apiKey);
  }

  static const _promptText = '''
You are a professional photo color-grading assistant.
Look at the attached photo and analyze its lighting and color.

For each of the following four adjustments, suggest a value between -100 and 100
(0 means "no change needed"), where the value represents a percentage adjustment:
- brightness
- saturation
- contrast
- sharpness

Also give a short reason for each suggestion, written in Traditional Chinese (繁體中文),
no more than 15 characters.

You MUST respond ONLY with a valid JSON object in exactly this shape:
{
  "brightness": {"value": float, "reason": "string in Traditional Chinese"},
  "saturation": {"value": float, "reason": "string in Traditional Chinese"},
  "contrast": {"value": float, "reason": "string in Traditional Chinese"},
  "sharpness": {"value": float, "reason": "string in Traditional Chinese"}
}

Do not include any image data, base64, or pixel values in your response — only the
numeric adjustment values and the short text reasons.
''';

  Future<ColorAdjustmentSuggestion> analyzeColors(Uint8List imageBytes) async {
    final prompt = TextPart(_promptText);
    final imagePart = DataPart('image/jpeg', imageBytes);

    late final String responseText;
    try {
      final response = await _model.generateContent([
        Content.multi([prompt, imagePart]),
      ]);
      responseText = response.text?.trim() ?? '';
    } catch (e) {
      throw GeminiColorRequestException(e.toString());
    }

    try {
      final cleaned = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      return ColorAdjustmentSuggestion.fromJson(data);
    } catch (e) {
      throw GeminiColorParseException(e.toString(), responseText);
    }
  }
}