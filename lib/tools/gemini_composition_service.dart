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
  final String name;
  final List<double> boundingBox;

  const DetectedSubject({
    required this.name,
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
      name: json['name'] as String? ?? '未知主體',
      boundingBox: parseBox(json['bounding_box']),
    );
  }
}

@immutable
class ActionPlan {
  final String selectedTool;
  final List<Movement> movements;
  final UiGuides uiGuides;

  const ActionPlan({
    required this.selectedTool,
    required this.movements,
    required this.uiGuides,
  });

  factory ActionPlan.fromJson(Map<String, dynamic> json) {
    return ActionPlan(
      selectedTool: json['selected_tool'] as String? ?? 'none',
      movements: (json['movements'] as List<dynamic>?)
              ?.map((e) => Movement.fromJson(e))
              .toList() ??
          [],
      uiGuides: UiGuides.fromJson(json['ui_guides'] ?? {}),
    );
  }
}

@immutable
class Movement {
  final String subjectName;
  final List<double> targetBoundingBox;
  final String directionHint;

  const Movement({
    required this.subjectName,
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
      subjectName: json['subject_name'] as String? ?? '',
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

  GeminiCompositionService({String modelName = 'gemini-2.5-flash-lite'})
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

  static const _promptText = '''
你是一個頂級的「AI 攝影代理人 (AI Photography Agent)」。你的任務是透過分析使用者的相機預覽畫面，自主規劃並給出最佳的構圖引導座標與攝影建議。

【你的可用工具箱 (Tools)】
你必須根據畫面場景，從以下工具中選擇「一個」最適合的構圖工具 (請輸出對應的 Tool_ID)：

▶ 人像場景 (Portrait)
- Tool_ID: "Portrait_RuleOfThirds" (三分法構圖)：將人物主體置於 3x3 交點處，畫面更穩定有張力，自然引導視線。
- Tool_ID: "Portrait_NegativeSpace" (留白構圖)：利用留白空間讓人物主體更清晰，營造簡約美感與故事性。
- Tool_ID: "Portrait_Framing" (框架構圖)：用窗框、樹枝或門框構成自然畫框突顯人物，加強畫面深度。

▶ 美食場景 (Food)
- Tool_ID: "Food_FlatLay" (鳥瞰圖)：從上方俯視拍攝，呈現食物排列與紋理，視覺重心落在中央。
- Tool_ID: "Food_Centered" (中心構圖)：把餐點放在畫面中心，對稱穩定，適合特寫。
- Tool_ID: "Food_Diagonal" (對角線構圖)：沿對角線排布元素，增強畫面的動感與延伸節奏感。

▶ 風景場景 (Landscape)
- Tool_ID: "Landscape_RuleOfThirds" (三分法構圖)：地平線與主題依三分法安排，前景與遠景層次明確。
- Tool_ID: "Landscape_Symmetry" (對稱構圖)：用左右或上下對稱的建築與景物營造寧靜穩定感。
- Tool_ID: "Landscape_LeadingLines" (引導線構圖)：讓道路、鐵軌或建築線條引導觀眾視線，帶出深度和方向感。

【你的思考與執行流程 (Agentic Flow)】
接收到照片後，嚴格執行以下四個步驟：
1. [感知]：辨識畫面中的主要物件、場景類型 (人像/美食/風景)，並執行光線分析與線條偵測，最後確認主體目前的螢幕座標位置與大小。
2. [推論]：評估目前畫面的缺點（如：主體偏離、失去平衡、未利用場景延伸感、距離過近或過遠）。
3. [工具調用]：決定調用上述哪一個 Tool_ID 來解決問題。
4. [輸出]：評估主體的「可移動性」。若主體不可動（如風景、建築），須引導「相機」移動；若主體可動（如人物、飯菜），可建議平移相機或微調物體。計算出主體建議的目標位置與目標大小，並給出具體的距離提示。

【輸出格式限制 (CRITICAL)】
你只能輸出純 JSON 格式的文字，絕對不能包含 Markdown 標記 (如 ```json) 或其他廢話。所有座標數值必須是 0.0 到 1.0 之間的浮點數（原點 0,0 位於左上角）。
"detected_subjects"跟"movements"的項目必須完全一致

【深度與框線大小規則 (Z-axis Depth)】
- 黃框 (bounding_box)：代表主體目前的位置與大小。
- 藍框 (target_bounding_box)：代表建議的目標位置與大小。
- 距離提示：
  - 如果你需要使用者「後退」(拉開空間)，藍框的長寬比例必須「小於」黃框。
  - 如果你需要使用者「靠近」(填滿畫面)，藍框的長寬比例必須「大於」黃框。
  - 如果只需平移，藍框大小需與黃框一致。

請嚴格遵守以下 Schema：

{
  "scene_type": "字串 (人像/美食/風景)",
  "reasoning_steps": [
    "[感知] 你的感知分析...",
    "[推論] 你的推論過程...",
    "[工具調用] 你決定調用的工具與原因..."
  ],
  "perception": {
    "detected_subjects": [
      {
        "name": "字串，主體名稱",
        "bounding_box": [x_min, y_min, x_max, y_max]
      }
    ]
  },
  "action_plan": {
    "selected_tool": "字串，必須是工具箱中的確切 Tool_ID",
    "movements": [
      {
        "subject_name": "字串，對應偵測到的主體",
        "target_bounding_box": [x_min, y_min, x_max, y_max],
        "direction_hint": "字串，包含具體平移與前後深度的提示。例如：向右平移並後退兩步，讓主體縮小對齊藍框。"
      }
    ],
    "ui_guides": {
      "show_grid": 布林值,
      "guide_lines": []
    }
  }
}

【範例學習 (Few-Shot Examples)】
範例一 (需要後退與平移的情境)：
輸入：一張拉麵拍得太近，且偏向畫面左下角的照片。
輸出：
{
  "scene_type": "美食",
  "reasoning_steps": [
    "[感知] 偵測到畫面主體為「拉麵」，目前佔據畫面比例過大，且重心偏向左下角。",
    "[推論] 需要拉開空間深度並適度留白，目前的構圖讓畫面顯得擁擠，右上角過於空洞。",
    "[工具調用] 決定調用「Food_Diagonal」，並要求使用者稍微後退以縮小主體比例，同時將主體引導至右上方。"
  ],
  "perception": {
    "detected_subjects": [
      {
        "name": "拉麵",
        "bounding_box": [0.10, 0.50, 0.80, 0.90] 
      }
    ]
  },
  "action_plan": {
    "selected_tool": "Food_Diagonal",
    "movements": [
      {
        "subject_name": "拉麵",
        "target_bounding_box": [0.60, 0.20, 0.90, 0.50],
        "direction_hint": "將相機向左下方平移，並向後退拉開距離，讓麵碗縮小至藍框大小"
      }
    ],
    "ui_guides": {
      "show_grid": false,
      "guide_lines": [{"start": [0.0, 1.0], "end": [1.0, 0.0]}]
    }
  }
}
''';

  Future<AiSuggestion> analyzeComposition(Uint8List imageBytes) async {
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
      
      // 直接轉換為強型別 Dart 物件
      return AiSuggestion.fromJson(data);
      
    } catch (e) {
      throw GeminiParseException(e.toString(), responseText);
    }
  }
}