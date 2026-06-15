/// This repository is for ai edit screen
/// in order to store user's preferences
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'photo_repo.dart' show kDeviceUserId; // TODO: check photo repo

/// 單筆風格記憶：一次編輯行為的場景特徵 + 使用者選擇的風格
@immutable
class StyleMemoryEntry {
  /// Gemini分析原圖後產出的場景特徵描述（英文，Unsplash搜尋關鍵詞）
  final String sceneFeatures;

  /// 使用者最終選擇的風格標籤（中文，例如「溫暖電影感」）
  final String chosenStyleLabel;

  /// 使用者最終選擇的風格搜尋關鍵詞（英文，例如 "warm cinematic sunset"）
  final String chosenStyleQuery;

  /// 使用者最終套用的調整數值
  final Map<String, double> finalAdjustments;

  /// 記錄時間
  final DateTime timestamp;

  const StyleMemoryEntry({
    required this.sceneFeatures,
    required this.chosenStyleLabel,
    required this.chosenStyleQuery,
    required this.finalAdjustments,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'sceneFeatures': sceneFeatures,
    'chosenStyleLabel': chosenStyleLabel,
    'chosenStyleQuery': chosenStyleQuery,
    'finalAdjustments': finalAdjustments,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  factory StyleMemoryEntry.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'];
    return StyleMemoryEntry(
      sceneFeatures: json['sceneFeatures'] as String? ?? '',
      chosenStyleLabel: json['chosenStyleLabel'] as String? ?? '',
      chosenStyleQuery: json['chosenStyleQuery'] as String? ?? '',
      finalAdjustments: (json['finalAdjustments'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  /// 把這筆記憶轉成一句自然語言，供注入Gemini prompt使用
  String toPromptLine() =>
      '- Scene: "$sceneFeatures" → User chose "$chosenStyleLabel" style';
}

/// 讀寫使用者風格選擇歷史的repository。
///
/// Firestore路徑：
/// `users/{userId}/style_memory/{docId}`
///
/// 這是agentic流程的Memory層：
/// 每次編輯完成後寫入一筆記錄，下次進編輯畫面時讀取最近N筆，
/// 注入Gemini的prompt讓AI能根據使用者偏好做出更個人化的推薦。
class StyleMemoryRepository {
  final FirebaseFirestore _db;
  final String _userId;

  StyleMemoryRepository({
    FirebaseFirestore? db,
    String? userId,
  })  : _db = db ?? FirebaseFirestore.instance,
        _userId = userId ?? kDeviceUserId;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(_userId).collection('style_memory');

  /// 寫入一筆風格記憶
  Future<void> save(StyleMemoryEntry entry) async {
    try {
      await _col.add(entry.toJson());
    } catch (e) {
      debugPrint('StyleMemoryRepository.save 失敗: $e');
    }
  }

  /// 讀取最近[limit]筆記憶（依時間倒序）
  Future<List<StyleMemoryEntry>> loadRecent({int limit = 5}) async {
    try {
      final snapshot = await _col
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => StyleMemoryEntry.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('StyleMemoryRepository.loadRecent 失敗: $e');
      return [];
    }
  }

  /// 把最近N筆記憶轉成可以注入Gemini prompt的文字段落。
  /// 如果沒有歷史記錄，回傳空字串（不影響prompt運作）。
  static String toPromptContext(List<StyleMemoryEntry> entries) {
    if (entries.isEmpty) return '';

    final lines = entries.map((e) => e.toPromptLine()).join('\n');
    return '''
This user's past style preferences (most recent first):
$lines

Use these preferences as a soft hint — if the current photo's scene is similar
to a past entry, lean toward that style direction. But still suggest 3 distinct
options so the user has real choices.
''';
  }
}