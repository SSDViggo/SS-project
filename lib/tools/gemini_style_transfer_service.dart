import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'gemini_color_service.dart' show ColorAdjustmentSuggestion;

class GeminiStyleTransferRequestException implements Exception {
  final String message;
  GeminiStyleTransferRequestException(this.message);

  @override
  String toString() => 'GeminiStyleTransferRequestException: $message';
}

class GeminiStyleTransferParseException implements Exception {
  final String message;
  final String rawResponse;
  GeminiStyleTransferParseException(this.message, this.rawResponse);

  @override
  String toString() => 'GeminiStyleTransferParseException: $message';
}

/// 比較「原圖」與使用者選擇的「參考圖」，輸出讓原圖朝參考圖風格調整的
/// 調色數值（brightness/saturation/contrast/sharpness）。
///
/// 這是agentic流程的第二個Reasoning步驟：輸入是兩張圖片，
/// 輸出仍然只是數值+理由，不包含任何圖片——
/// 實際的影像渲染交由本地的[ImageProcessingService]處理。
class GeminiStyleTransferService {
  late final GenerativeModel _model;
  final bool hasApiKey;

  GeminiStyleTransferService({String modelName = 'gemini-2.5-flash-lite'})
      : hasApiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').isNotEmpty {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (!hasApiKey) {
      debugPrint('警告：找不到 GEMINI_API_KEY，請檢查 .env 檔案設定。');
    }
    _model = GenerativeModel(model: modelName, apiKey: apiKey);
  }

  static const _promptText = '''
You are a professional photo color-grading assistant.

You are given TWO images:
1. The FIRST image is the user's ORIGINAL photo.
2. The SECOND image is a REFERENCE photo showing a mood/style the user likes.

Analyze the color and lighting DIFFERENCE between the two images, and figure out
what adjustments to the ORIGINAL photo would make it FEEL closer to the
REFERENCE photo's mood/style (without changing its actual content/subject).

For each of the following four adjustments, suggest a value between -100 and 100
(0 means "no change needed"), where the value represents a percentage adjustment
to apply to the ORIGINAL photo:
- brightness
- saturation
- contrast
- sharpness

Also give a short reason for each suggestion, written in Traditional Chinese (繁體中文),
no more than 15 characters, explaining how it moves toward the reference style.

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

  /// 比較原圖與參考圖，回傳調色建議（數值+理由）。
  ///
  /// 拋出[GeminiStyleTransferRequestException]代表API呼叫本身失敗。
  /// 拋出[GeminiStyleTransferParseException]代表回應內容不是預期的JSON格式。
  Future<ColorAdjustmentSuggestion> analyze({
    required Uint8List originalImageBytes,
    required Uint8List referenceImageBytes,
  }) async {
    final prompt = TextPart(_promptText);
    final originalPart = DataPart('image/jpeg', originalImageBytes);
    final referencePart = DataPart('image/jpeg', referenceImageBytes);

    late final String responseText;
    try {
      final response = await _model.generateContent([
        Content.multi([prompt, originalPart, referencePart]),
      ]);
      responseText = response.text?.trim() ?? '';
    } catch (e) {
      throw GeminiStyleTransferRequestException(e.toString());
    }

    try {
      final cleaned = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      return ColorAdjustmentSuggestion.fromJson(data);
    } catch (e) {
      throw GeminiStyleTransferParseException(e.toString(), responseText);
    }
  }
}