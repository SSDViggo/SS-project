import 'package:flutter/material.dart';

class CameraProvider extends ChangeNotifier {
  String? _lastCapturePath;
  bool _isProcessing = false;
  Map<String, dynamic> _currentEnhancements = {
    'brightness': 0,
    'saturation': 0,
    'contrast': 0,
    'sharpness': 0,
  };

  String? get lastCapturePath => _lastCapturePath;
  bool get isProcessing => _isProcessing;
  Map<String, dynamic> get currentEnhancements => _currentEnhancements;

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
