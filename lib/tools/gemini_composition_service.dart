import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// 呼叫Gemini API失敗時拋出（網路/連線層級的錯誤）
class GeminiRequestException implements Exception {
  final String message;
  GeminiRequestException(this.message);

  @override
  String toString() => 'GeminiRequestException: $message';
}

/// Gemini有回應，但回應內容無法解析成預期格式時拋出
class GeminiParseException implements Exception {
  final String message;
  final String rawResponse;
  GeminiParseException(this.message, this.rawResponse);

  @override
  String toString() => 'GeminiParseException: $message';
}

/// Gemini針對單張相機畫面回傳的構圖建議。
///
/// 所有欄位在解析時都做了null防呆，缺漏的欄位會用[fallback]裡的舊值
/// （或合理的預設值）填補，確保呼叫端不會因為AI回傳格式不完整而crash。
@immutable
class CompositionSuggestion {
  /// AI判斷出的主體描述
  final String detectedSubject;

  /// 推薦的構圖技巧名稱（繁體中文，會顯示在對話框標題）
  final String technique;

  /// 給使用者的具體建議文字（繁體中文）
  final String tip;

  /// 建議的主體理想位置，正規化座標 (0.0 ~ 1.0)
  final double idealX;
  final double idealY;

  /// 對應 [CompositionOverlayManager] 的網格樣式
  /// 必須是 'rule_of_thirds' / 's_curve' / 'triangle' / 'symmetry' / 'none' 之一
  final String patternType;

  /// 建議的曝光補償 (-2.0 ~ 2.0)
  final double evOffset;

  /// 是否建議開啟閃光燈
  final bool flashOn;

  /// 場景描述（例如「夜景模式」），用於UI提示
  final String sceneMode;

  const CompositionSuggestion({
    required this.detectedSubject,
    required this.technique,
    required this.tip,
    required this.idealX,
    required this.idealY,
    required this.patternType,
    required this.evOffset,
    required this.flashOn,
    required this.sceneMode,
  });

  /// 從Gemini回傳的JSON建立[CompositionSuggestion]。
  ///
  /// - [idealX]/[idealY] 缺漏時，使用[fallbackX]/[fallbackY]（通常是目前畫面上的值）
  /// - 其他欄位缺漏時，使用合理的預設文字/數值
  factory CompositionSuggestion.fromJson(
    Map<String, dynamic> json, {
    required double fallbackX,
    required double fallbackY,
  }) {
    return CompositionSuggestion(
      detectedSubject: json['detected_subject'] as String? ?? '未知主體',
      technique: json['composition_technique'] as String? ?? '未知構圖',
      tip: json['actionable_tip'] as String? ?? '暫無建議',
      idealX: (json['ideal_x'] as num?)?.toDouble() ?? fallbackX,
      idealY: (json['ideal_y'] as num?)?.toDouble() ?? fallbackY,
      patternType: json['patternType'] as String? ?? 'none',
      evOffset: (json['ev_offset'] as num?)?.toDouble() ?? 0.0,
      flashOn: json['flash_on'] as bool? ?? false,
      sceneMode: json['scene_mode'] as String? ?? '一般模式',
    );
  }
}

/// 封裝與Gemini溝通、取得拍攝構圖建議的service。
///
/// UI層只需要呼叫[analyzeComposition]，傳入目前畫面的PNG截圖，
/// 即可拿到結構化的[CompositionSuggestion]，不需要關心prompt內容、
/// API呼叫細節或JSON解析邏輯。
class GeminiCompositionService {
  late final GenerativeModel _model;

  /// 是否已成功讀取到API Key（沒有的話呼叫API一定會失敗）
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
You are a professional photography assistant. 
Look at the attached camera preview image. The user's intended main subject is highlighted with a yellow marker.

Please perform the following tasks:
1. Identify the main subject.
2. Analyze the scene to choose the BEST composition technique.
3. Determine the ideal coordinates (x, y) for the subject (0.0 to 1.0).
4. Decide if the exposure needs adjustment (-2.0 to 2.0) or if the flash is needed based on the lighting.

You MUST respond ONLY with a valid JSON object:
{
  "detected_subject": "string",
  "composition_technique": "string (in Traditional Chinese)",
  "patternType": "string (MUST be one of: 'rule_of_thirds', 's_curve', 'triangle', 'symmetry', 'none')",
  "ideal_x": float (0.0 to 1.0),
  "ideal_y": float (0.0 to 1.0),
  "actionable_tip": "string (in Traditional Chinese)",
  "ev_offset": float (-2.0 to 2.0),
  "flash_on": boolean,
  "scene_mode": "string (e.g., 夜景模式, 逆光人像, 晴天風景)"
}
''';

  /// 將目前畫面的PNG截圖送給Gemini，取得構圖建議。
  ///
  /// [fallbackX]/[fallbackY] 會在AI沒有回傳座標時被使用，
  /// 通常傳入目前畫面上「AI建議位置」的座標即可。
  ///
  /// 拋出[GeminiRequestException]代表API呼叫本身失敗（例如網路問題）。
  /// 拋出[GeminiParseException]代表API有回應，但內容不是預期的JSON格式。
  Future<CompositionSuggestion> analyzeComposition(
    Uint8List pngBytes, {
    required double fallbackX,
    required double fallbackY,
  }) async {
    final prompt = TextPart(_promptText);
    final imagePart = DataPart('image/png', pngBytes);

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
      // 清除Gemini可能回傳的markdown json標記後再解析
      final cleaned = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      return CompositionSuggestion.fromJson(
        data,
        fallbackX: fallbackX,
        fallbackY: fallbackY,
      );
    } catch (e) {
      throw GeminiParseException(e.toString(), responseText);
    }
  }
}
