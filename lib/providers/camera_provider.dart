import 'package:flutter/material.dart';
import '../tools/gemini_color_service.dart';

/// 管理相機拍攝結果、圖庫照片清單，以及編輯畫面的AI建議/手動調整狀態。
class CameraProvider extends ChangeNotifier {
  String? _lastCapturePath;
  bool _isProcessing = false;
  final List<String> _capturedPhotos = [];

  /// 手動調整的數值（亮度/飽和度/對比度/銳度），範圍-100~100
  Map<String, double> _currentEnhancements = {
    'brightness': 0,
    'saturation': 0,
    'contrast': 0,
    'sharpness': 0,
  };

  /// AI建議是否被使用者勾選套用（與[_currentEnhancements]分開存放，
  /// 避免「是否套用(bool)」與「調整數值(double)」共用同一個欄位造成型別衝突）
  Map<String, bool> _appliedSuggestions = {
    'brightness': false,
    'saturation': false,
    'contrast': false,
    'sharpness': false,
  };

  ColorAdjustmentSuggestion? _colorSuggestion;
  bool _isAnalyzingColor = false;
  String? _lastEditedPath;

  String? get lastCapturePath => _lastCapturePath;
  bool get isProcessing => _isProcessing;
  Map<String, double> get currentEnhancements => _currentEnhancements;
  Map<String, bool> get appliedSuggestions => _appliedSuggestions;
  List<String> get capturedPhotos => List.unmodifiable(_capturedPhotos);
  ColorAdjustmentSuggestion? get colorSuggestion => _colorSuggestion;
  bool get isAnalyzingColor => _isAnalyzingColor;
  String? get lastEditedPath => _lastEditedPath;

  /// 開始編輯一張照片：如果跟上次編輯的不是同一張，重置所有調整狀態
  void startEditing(String? path) {
    if (path != _lastEditedPath) {
      resetEnhancements();
      _lastEditedPath = path;
    }
  }

  /// 新增一張剛拍好的照片路徑（會插入到清單最前面，最新的排前面）
  void addPhoto(String path) {
    _capturedPhotos.insert(0, path);
    _lastCapturePath = path;
    notifyListeners();
  }

  /// 從清單中移除一張照片（不會刪除實體檔案）
  void removePhoto(String path) {
    _capturedPhotos.remove(path);
    notifyListeners();
  }

  void setLastCapturePath(String path) {
    _lastCapturePath = path;
    notifyListeners();
  }

  void setProcessing(bool value) {
    _isProcessing = value;
    notifyListeners();
  }

  /// 設定一次新的AI調色建議（呼叫[GeminiColorService]成功後使用）。
  /// 直接讓gemini推薦的數值順利呈現在slider上
  void setColorSuggestion(ColorAdjustmentSuggestion suggestion) {
    _colorSuggestion = suggestion;
    _currentEnhancements = {
      'brightness': suggestion.brightness.value,
      'saturation': suggestion.saturation.value,
      'contrast': suggestion.contrast.value,
      'sharpness': suggestion.sharpness.value,
    };
    notifyListeners();
  }

  void setAnalyzingColor(bool value) {
    _isAnalyzingColor = value;
    notifyListeners();
  }

  /// 取得某個調整項目的「有效數值」：手動調整值 + （若勾選套用）AI建議值，
  /// 並clamp在-100~100之間。這個值才是實際要拿去算Color Matrix的數值。
  double effectiveValue(String key) {
    final manual = _currentEnhancements[key] ?? 0.0;
    final applied = _appliedSuggestions[key] ?? false;
    final suggestion = _colorSuggestion;
    if (!applied || suggestion == null) return manual;

    double aiValue;
    switch (key) {
      case 'brightness':
        aiValue = suggestion.brightness.value;
        break;
      case 'saturation':
        aiValue = suggestion.saturation.value;
        break;
      case 'contrast':
        aiValue = suggestion.contrast.value;
        break;
      case 'sharpness':
        aiValue = suggestion.sharpness.value;
        break;
      default:
        aiValue = 0.0;
    }
    return (manual + aiValue).clamp(-100, 100);
  }

  /// 更新手動調整的數值（亮度/飽和度/對比度/銳度）。
  /// 將-0.0正規化為0.0，避免Slider拖動經過0時短暫顯示「-0」。
  void updateEnhancement(String key, double value) {
    _currentEnhancements[key] = value == 0 ? 0.0 : value;
    notifyListeners();
  }

  /// 切換某項AI建議是否被勾選套用
  void toggleSuggestion(String key, bool applied) {
    _appliedSuggestions[key] = applied;
    notifyListeners();
  }

  void resetEnhancements() {
    _currentEnhancements = {
      'brightness': 0,
      'saturation': 0,
      'contrast': 0,
      'sharpness': 0,
    };
    _appliedSuggestions = {
      'brightness': false,
      'saturation': false,
      'contrast': false,
      'sharpness': false,
    };
    _colorSuggestion = null;
    notifyListeners();
  }
}