import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'object_detector_service.dart'; // ⭐️ 引入 ML Kit 的 NormalizedBox 類別

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
class AiSuggestion {
  final String sceneType;
  final List<String> reasoningSteps;
  final Perception perception;
  final ActionPlan actionPlan;

  const AiSuggestion({
    required this.sceneType,
    required this.reasoningSteps,
    required this.perception,
    required this.actionPlan,
  });

  factory AiSuggestion.fromJson(Map<String, dynamic> json) {
    return AiSuggestion(
      sceneType: json['scene_type'] as String? ?? '未知場景',
      reasoningSteps: (json['reasoning_steps'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      perception: Perception.fromJson(json['perception'] ?? {}),
      actionPlan: ActionPlan.fromJson(json['action_plan'] ?? {}),
    );
  }
}

@immutable
class Perception {
  final List<DetectedSubject> detectedSubjects;

  const Perception({required this.detectedSubjects});

  factory Perception.fromJson(Map<String, dynamic> json) {
    return Perception(
      detectedSubjects: (json['detected_subjects'] as List<dynamic>?)
              ?.map((e) => DetectedSubject.fromJson(e))
              .toList() ??
          [],
    );
  }
}

@immutable
class DetectedSubject {
  final int trackingId;     // ⭐️ 新增：綁定 ML Kit 的 ID
  final String label;       // ⭐️ 新增：取代原本的 name
  final bool isMainSubject; // ⭐️ 新增：確認是否為核心主體
  final List<double> boundingBox;

  const DetectedSubject({
    required this.trackingId,
    required this.label,
    required this.isMainSubject,
    required this.boundingBox,
  });

  factory DetectedSubject.fromJson(Map<String, dynamic> json) {
    List<double> parseBox(dynamic boxData) {
      if (boxData is List && boxData.length >= 4) {
        return boxData.map((e) => (e as num).toDouble()).take(4).toList();
      }
      return [0.0, 0.0, 0.0, 0.0];
    }

    return DetectedSubject(
      trackingId: json['tracking_id'] as int? ?? -1,
      label: json['label'] as String? ?? '未知主體',
      isMainSubject: json['is_main_subject'] as bool? ?? false,
      boundingBox: parseBox(json['bounding_box']),
    );
  }
}

@immutable
class ActionPlan {
  final String selectedTool;
  final List<Movement> movements;
  final UiGuides uiGuides;
  final List<int> ignoredTrackingIds;

  const ActionPlan({
    required this.selectedTool,
    required this.movements,
    required this.uiGuides,
    required this.ignoredTrackingIds,
  });

  factory ActionPlan.fromJson(Map<String, dynamic> json) {
    return ActionPlan(
      selectedTool: json['selected_tool'] as String? ?? 'none',
      movements: (json['movements'] as List<dynamic>?)
              ?.map((e) => Movement.fromJson(e))
              .toList() ??
          [],
      uiGuides: UiGuides.fromJson(json['ui_guides'] ?? {}),
      ignoredTrackingIds: (json['ignored_tracking_ids'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
  }
}

@immutable
class Movement {
  final int trackingId; // ⭐️ 新增：取代 subjectName，用 ID 精準鎖定
  final List<double> targetBoundingBox;
  final String directionHint;

  const Movement({
    required this.trackingId,
    required this.targetBoundingBox,
    required this.directionHint,
  });

  factory Movement.fromJson(Map<String, dynamic> json) {
    List<double> parseBox(dynamic boxData) {
      if (boxData is List && boxData.length >= 4) {
        return boxData.map((e) => (e as num).toDouble()).take(4).toList();
      }
      return [0.0, 0.0, 0.0, 0.0];
    }

    return Movement(
      trackingId: json['tracking_id'] as int? ?? -1,
      targetBoundingBox: parseBox(json['target_bounding_box']),
      directionHint: json['direction_hint'] as String? ?? '',
    );
  }
}

@immutable
class UiGuides {
  final bool showGrid;
  final List<GuideLine> guideLines;

  const UiGuides({
    required this.showGrid,
    required this.guideLines,
  });

  factory UiGuides.fromJson(Map<String, dynamic> json) {
    return UiGuides(
      showGrid: json['show_grid'] as bool? ?? false,
      guideLines: (json['guide_lines'] as List<dynamic>?)
              ?.map((e) => GuideLine.fromJson(e))
              .toList() ??
          [],
    );
  }
}

@immutable
class GuideLine {
  final List<double> start;
  final List<double> end;

  const GuideLine({
    required this.start,
    required this.end,
  });

  factory GuideLine.fromJson(Map<String, dynamic> json) {
    List<double> parsePoint(dynamic pointData) {
      if (pointData is List && pointData.length >= 2) {
        return pointData.map((e) => (e as num).toDouble()).take(2).toList();
      }
      return [0.0, 0.0];
    }

    return GuideLine(
      start: parsePoint(json['start']),
      end: parsePoint(json['end']),
    );
  }
}

class GeminiCompositionService {
  late final GenerativeModel _model;
  final bool hasApiKey;

  GeminiCompositionService({String modelName = 'gemini-2.5-flash'})
      : hasApiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').isNotEmpty {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (!hasApiKey) {
      debugPrint('警告：找不到 GEMINI_API_KEY，請檢查 .env 檔案設定。');
    }

    _model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  // ⭐️ 替換為最新升級版，包含動態 {{DETECTED_BOXES}} 的 Prompt
  static const _promptTemplate = '''
你是一個頂級的「AI Photography Agent」。你的任務是透過分析使用者的相機畫面，以及系統預先提供給你的物件邊界框 (Bounding Box)，自主規劃並給出最佳的構圖引導座標與攝影建議。

【動態輸入資料】
我會附上一張目前的預覽畫面照片，並且系統已經在畫面中標記了以下潛在物件的位置與 Tracking ID：
{{DETECTED_BOXES}}
(格式為：ID: [x_min, y_min, x_max, y_max])

【例外處理 (寧缺勿濫機制) - CRITICAL】
你必須擁有「寧缺勿濫」的判斷力。
1. 絕對禁止鎖定背景：絕對不可以選擇「環境結構與背景」（例如：窗戶、地板、牆壁、天花板、地毯、巨大的空書櫃）作為主體。
2. 拒絕妥協：如果你發現照片中有真正的主體（例如小貓咪），但系統提供的 Bounding Box 列表卻「沒 有任何一個框」能剛好且緊密地包覆牠（例如只框住了整個窗戶或地板）：
   - 請強制將主體與 movement 的 `tracking_id` 設為 `-1` (代表拒絕鎖定錯誤的框)。
   - 將那些巨大的背景框 ID (如窗戶、地板) 全部放入 `ignored_tracking_ids` 黑名單中。
   - 在 `direction_hint` 強烈提示：「請向前靠近 [真正的主體名稱]，讓系統能成功辨識」。

【你的可用工具箱 (Tools)】
你必須根據畫面場景，從以下工具中選擇「一個」最適合的構圖工具 (請輸出對應的 Tool_ID)：

▶ 人像場景 (Portrait)
- Tool_ID: "Portrait_RuleOfThirds" (三分法)
- Tool_ID: "Portrait_NegativeSpace" (留白)
- Tool_ID: "Portrait_Framing" (框架)

▶ 美食場景 (Food)
- Tool_ID: "Food_FlatLay" (鳥瞰)
- Tool_ID: "Food_Centered" (中心)
- Tool_ID: "Food_Diagonal" (對角線)

▶ 風景場景 (Landscape)
- Tool_ID: "Landscape_RuleOfThirds" (三分法)
- Tool_ID: "Landscape_Symmetry" (對稱)
- Tool_ID: "Landscape_LeadingLines" (引導線)

【你的思考與執行流程 (Agentic Flow)】
接收到照片與邊界框數據後，嚴格執行以下四個步驟：
1. [感知]：辨識場景與主體。如果沒有合適的框，啟用寧缺勿濫機制。
2. [推論]：評估構圖缺點。
3. [工具調用]：選擇 Tool_ID。
4. [輸出]：給出目標座標與具體提示。

【輸出格式限制 (CRITICAL)】
只能輸出純 JSON 格式的文字，不能包含 Markdown 標記 (如 ```json)。所有座標必須是 0.0 到 1.0 的浮點數。
請嚴格遵守以下 Schema (注意 tracking_id 可以為 -1)：

{
  "scene_type": "字串 (人像/美食/風景)",
  "reasoning_steps": [
    "[感知] ...",
    "[推論] ...",
    "[工具調用] ..."
  ],
  "perception": {
    "detected_subjects": [
      {
        "tracking_id": 整數 (若無合適框請填 -1),
        "label": "字串，精準物件名稱",
        "is_main_subject": 布林值,
        "bounding_box": [x_min, y_min, x_max, y_max] // ⭐️ 即使 tracking_id 為 -1，也請你憑藉視覺能力，自己填入該主體在畫面中的實際座標！
      }
    ]
  },
  "action_plan": {
    "selected_tool": "確切 Tool_ID",
    "ignored_tracking_ids": [整數, 整數], // 背景或雜物的 ID
    "movements": [
      {
        "tracking_id": 整數 (對應主體的 ID，可為 -1),
        "target_bounding_box": [x_min, y_min, x_max, y_max],
        "direction_hint": "具體的提示..."
      }
    ],
    "ui_guides": {
      "show_grid": 布林值,
      "guide_lines": []
    }
  }
}

【範例學習 (Few-Shot Examples)】
範例一：正常情況
動態輸入：
ID 1: [0.10, 0.50, 0.80, 0.90] (拉麵)
ID 2: [0.70, 0.10, 0.85, 0.30] (茶杯)
輸出 JSON：
{
  "scene_type": "美食",
  "reasoning_steps": [ "[感知] ID 1 為拉麵，設為主體...", "[推論] 畫面擁擠...", "[工具調用] 調用 Food_Diagonal" ],
  "perception": {
    "detected_subjects": [
      { "tracking_id": 1, "label": "拉麵", "is_main_subject": true, "bounding_box": [0.10, 0.50, 0.80, 0.90] },
      { "tracking_id": 2, "label": "茶杯", "is_main_subject": false, "bounding_box": [0.70, 0.10, 0.85, 0.30] }
    ]
  },
  "action_plan": {
    "selected_tool": "Food_Diagonal",
    "ignored_tracking_ids": [2],
    "movements": [ { "tracking_id": 1, "target_bounding_box": [0.60, 0.20, 0.90, 0.50], "direction_hint": "相機向左下平移並後退" } ],
    "ui_guides": { "show_grid": false, "guide_lines": [] }
  }
}

範例二：主體太小，啟動寧缺勿濫 (-1 機制)
動態輸入：
ID 15: [0.10, 0.20, 0.90, 0.80] (窗戶)
ID 7: [0.70, 0.10, 0.95, 0.90] (書櫃)
(畫面中有一隻小貓，但沒有對應的 ID)
輸出 JSON：
{
  "scene_type": "人像",
  "reasoning_steps": [ "[感知] 畫面上有一隻小貓，但 ID 15 是窗戶、ID 7 是書櫃，無適合框，啟用寧缺勿濫機制。", "[推論] 貓咪過小無法追蹤。", "[工具調用] 選擇 Portrait_RuleOfThirds" ],
  "perception": {
    "detected_subjects": [
      { "tracking_id": -1, "label": "小貓", "is_main_subject": true, "bounding_box": [0.55, 0.60, 0.65, 0.75] }
    ]
  },
  "action_plan": {
    "selected_tool": "Portrait_RuleOfThirds",
    "ignored_tracking_ids": [15, 7],
    "movements": [ { "tracking_id": -1, "target_bounding_box": [0.50, 0.50, 0.80, 0.80], "direction_hint": "請向前靠近 小貓，讓系統能成功辨識" } ],
    "ui_guides": { "show_grid": true, "guide_lines": [] }
  }
}
''';
  /// ⭐️ 輔助方法：將傳入的 NormalizedBox 陣列轉為純文字，供 Prompt 使用
  String _generateDetectedBoxesText(List<NormalizedBox> boxes) {
    if (boxes.isEmpty) return "目前未偵測到任何明確物件。";
    
    StringBuffer sb = StringBuffer();
    for (var box in boxes) {
      // 限制小數點位數，減少 Token 消耗
      final left = box.rect.left.toStringAsFixed(2);
      final top = box.rect.top.toStringAsFixed(2);
      final right = box.rect.right.toStringAsFixed(2);
      final bottom = box.rect.bottom.toStringAsFixed(2);
      
      sb.writeln("ID ${box.trackingId}: [$left, $top, $right, $bottom]");
    }
    return sb.toString();
  }

  /// ⭐️ 核心方法：加入 boxes 參數
  Future<AiSuggestion> analyzeComposition(Uint8List imageBytes, List<NormalizedBox> boxes) async {
    // 1. 動態組裝 Prompt
    final boxesText = _generateDetectedBoxesText(boxes);
    final finalPrompt = _promptTemplate.replaceAll('{{DETECTED_BOXES}}', boxesText);
    
    debugPrint('=== 發送給 Gemini 的動態 Boxes ===\n$boxesText');

    final prompt = TextPart(finalPrompt);
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
      
      // 直接轉換為強型別 Dart 物件
      return AiSuggestion.fromJson(data);
      
    } catch (e) {
      throw GeminiParseException(e.toString(), responseText);
    }
  }
}