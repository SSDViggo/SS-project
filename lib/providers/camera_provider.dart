// import 'package:flutter/material.dart';

// class CameraProvider extends ChangeNotifier {
//   String? _lastCapturePath;
//   bool _isProcessing = false;
//   Map<String, dynamic> _currentEnhancements = {
//     'brightness': 0,
//     'saturation': 0,
//     'contrast': 0,
//     'sharpness': 0,
//   };

//   String? get lastCapturePath => _lastCapturePath;
//   bool get isProcessing => _isProcessing;
//   Map<String, dynamic> get currentEnhancements => _currentEnhancements;

//   void setLastCapturePath(String path) {
//     _lastCapturePath = path;
//     notifyListeners();
//   }

//   void setProcessing(bool value) {
//     _isProcessing = value;
//     notifyListeners();
//   }

//   void updateEnhancement(String key, dynamic value) {
//     _currentEnhancements[key] = value;
//     notifyListeners();
//   }

//   void resetEnhancements() {
//     _currentEnhancements = {
//       'brightness': 0,
//       'saturation': 0,
//       'contrast': 0,
//       'sharpness': 0,
//     };
//     notifyListeners();
//   }
// }

import 'package:flutter/material.dart';

class CameraProvider extends ChangeNotifier {
  String? _lastCapturePath;
  bool _isProcessing = false;
  final List<String> _capturedPhotos = [];
  Map<String, dynamic> _currentEnhancements = {
    'brightness': 0,
    'saturation': 0,
    'contrast': 0,
    'sharpness': 0,
  };

  String? get lastCapturePath => _lastCapturePath;
  bool get isProcessing => _isProcessing;
  Map<String, dynamic> get currentEnhancements => _currentEnhancements;
  List<String> get capturedPhotos => List.unmodifiable(_capturedPhotos);

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

  void updateEnhancement(String key, dynamic value) {
    _currentEnhancements[key] = value;
    notifyListeners();
  }

  void resetEnhancements() {
    _currentEnhancements = {
      'brightness': 0,
      'saturation': 0,
      'contrast': 0,
      'sharpness': 0,
    };
    notifyListeners();
  }
}