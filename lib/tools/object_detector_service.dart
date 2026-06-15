import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

/// ⭐️ 1. 新增 NormalizedBox：綁定 ID 與 座標，給 CameraScreen 畫框用
class NormalizedBox {
  final int trackingId;
  final Rect rect;

  NormalizedBox({required this.trackingId, required this.rect});
}

class DetectionResult {
  final Offset position;
  final String label;
  final List<NormalizedBox> allBoxes; // ⭐️ 從 allRects 改為 allBoxes

  DetectionResult({required this.position, required this.label, required this.allBoxes});
}

class ObjectDetectorService {
  late ObjectDetector _objectDetector;
  bool _isInitialized = false;
  
  int? _lockedTrackingId; 
  String _targetLabel = '尋找目標中...'; 
  
  // ⭐️ 2. 新增：AI 霸體鎖定開關
  bool _isAiLocked = false; 

  double? _smoothedX;
  double? _smoothedY;
  final double _alpha = 0.25;

  void initialize() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,  
      multipleObjects: true,  
    );
    _objectDetector = ObjectDetector(options: options);
    _isInitialized = true;
  }

  void dispose() {
    if (_isInitialized) {
      _objectDetector.close();
      _isInitialized = false;
    }
    resetLock();
  }

  void resetLock() {
    _lockedTrackingId = null;
    _targetLabel = '尋找目標中...';
    _isAiLocked = false; // 解除 AI 鎖定
    _smoothedX = null;
    _smoothedY = null;
  }

  // ⭐️ 3. 提供給 Gemini 鎖定的專屬方法
  void lockTargetFromGemini(int trackingId, String label) {
    _lockedTrackingId = trackingId;
    _targetLabel = label;
    _isAiLocked = true; // 啟動霸體！絕對不允許被其他物件搶走 ID
  }

  Future<DetectionResult?> detectMainSubject({
    required CameraImage image,
    required CameraDescription camera,
    required Orientation deviceOrientation,
  }) async {
    if (!_isInitialized) return null;

    final inputImage = _inputImageFromCameraImage(image, camera);
    if (inputImage == null) return null;

    final List<DetectedObject> objects = await _objectDetector.processImage(inputImage);

    // 處理座標正規化轉換
    final imgWidth = image.width.toDouble();
    final imgHeight = image.height.toDouble();
    final sensorOrientation = camera.sensorOrientation;
    var rotationCompensation = 0;
    
    if (Platform.isAndroid) {
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + 0) % 360;
      } else {
        rotationCompensation = (sensorOrientation - 0 + 360) % 360;
      }
    } else if (Platform.isIOS) {
      rotationCompensation = sensorOrientation;
    }

    double domainWidth = imgWidth;
    double domainHeight = imgHeight;
    
    if (rotationCompensation == 90 || rotationCompensation == 270) {
      domainWidth = imgHeight;
      domainHeight = imgWidth;
    }

    Offset transform(double rawPxX, double rawPxY) {
      double nx = rawPxX / domainWidth;
      double ny = rawPxY / domainHeight;
      if (camera.lensDirection == CameraLensDirection.front) {
        nx = 1.0 - nx;
      }
      return Offset(nx, ny);
    }

    // 取得所有正規化後的框與 ID
    List<NormalizedBox> allNormalizedBoxes = [];
    for (var obj in objects) {
      if (obj.trackingId == null) continue;
      final r = obj.boundingBox;
      allNormalizedBoxes.add(NormalizedBox(
        trackingId: obj.trackingId!,
        rect: Rect.fromPoints(
          transform(r.left, r.top), 
          transform(r.right, r.bottom)
        ),
      ));
    }

    if (objects.isEmpty) {
      return DetectionResult(
        position: Offset(_smoothedX ?? 0.5, _smoothedY ?? 0.5),
        label: _targetLabel,
        allBoxes: allNormalizedBoxes,
      );
    }

    // --- ⭐️ 4. 尋找與鎖定邏輯 (強化版) ---
    DetectedObject? targetObject;
    
    // 優先找被鎖定的 ID
    if (_lockedTrackingId != null) {
      targetObject = objects.where((obj) => obj.trackingId == _lockedTrackingId).firstOrNull;
    }

    // 如果目標丟失了...
    if (targetObject == null) {
      if (_isAiLocked) {
        // 🚨 狀況 A：AI 已經鎖定了。絕對不能抓中間的窗戶！
        // 尋回策略：在「最後消失的位置」附近尋找有沒有新出現的物體
        if (_smoothedX != null && _smoothedY != null) {
          double bestDist = 0.05; // 允許的最大跳動半徑 (距離平方)
          for (var obj in objects) {
            final rect = obj.boundingBox;
            final pos = transform(rect.left + rect.width / 2, rect.top + rect.height / 2);
            final distSq = pow(pos.dx - _smoothedX!, 2) + pow(pos.dy - _smoothedY!, 2).toDouble();
            
            if (distSq < bestDist) {
              bestDist = distSq;
              targetObject = obj;
            }
          }
        }

        if (targetObject != null) {
          // 成功找回！更新為 ML Kit 賦予的新 ID，繼續死死咬住貓咪
          _lockedTrackingId = targetObject.trackingId;
        }
        // 如果還是找不到 (targetObject 依然為 null)，就不做任何事，保持黃框在原地等待。
        
      } else {
        // 🚨 狀況 B：還在 Live 自由探索模式 (AI 尚未指定) -> 找最中間的物體
        double bestDist = double.infinity;
        final centerImageX = domainWidth / 2;
        final centerImageY = domainHeight / 2;
        
        for (var obj in objects) {
          final rect = obj.boundingBox;
          final cx = rect.left + (rect.width / 2);
          final cy = rect.top + (rect.height / 2);
          final distToCenterSq = pow(cx - centerImageX, 2) + pow(cy - centerImageY, 2).toDouble();
          
          if (distToCenterSq < bestDist) {
            bestDist = distToCenterSq;
            targetObject = obj;
          }
        }
        if (targetObject != null) {
          _lockedTrackingId = targetObject.trackingId; // 更新臨時追蹤 ID
        }
      }
    }

    // --- 計算座標與 EMA 平滑化 ---
    if (targetObject != null) {
      final rect = targetObject.boundingBox;
      final centerX = rect.left + (rect.width / 2);
      final centerY = rect.top + (rect.height / 2);
      final rawPos = transform(centerX, centerY);

      if (_smoothedX == null || _smoothedY == null) {
        _smoothedX = rawPos.dx;
        _smoothedY = rawPos.dy;
      } else {
        _smoothedX = _alpha * rawPos.dx + (1 - _alpha) * _smoothedX!;
        _smoothedY = _alpha * rawPos.dy + (1 - _alpha) * _smoothedY!;
      }
    }

    String displayLabel = _targetLabel;
    if (!_isAiLocked && targetObject != null && targetObject.labels.isNotEmpty) {
      displayLabel = targetObject.labels.first.text;
    }

    return DetectionResult(
      position: Offset(_smoothedX ?? 0.5, _smoothedY ?? 0.5),
      label: displayLabel,
      allBoxes: allNormalizedBoxes,
    );
  }

  // ... 以下保留原本的 _inputImageFromCameraImage 與 _bytesFromCameraImage 不變 ...
  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + 0) % 360;
      } else {
        rotationCompensation = (sensorOrientation - 0 + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;
    if (image.planes.isEmpty) return null;

    final format = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final bytes = Platform.isAndroid ? _bytesFromCameraImage(image) : image.planes[0].bytes;

    if (bytes == null) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Uint8List? _bytesFromCameraImage(CameraImage image) {
    if (image.planes.length < 3) return null;
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 2;
    final Uint8List nv21 = Uint8List(ySize + uvSize);
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];
    int destinationIndex = 0;
    for (int row = 0; row < height; row++) {
      final int rowStart = row * yPlane.bytesPerRow;
      nv21.setRange(destinationIndex, destinationIndex + width, yPlane.bytes, rowStart);
      destinationIndex += width;
    }
    final int chromaHeight = height ~/ 2;
    final int chromaWidth = width ~/ 2;
    for (int row = 0; row < chromaHeight; row++) {
      for (int col = 0; col < chromaWidth; col++) {
        final int vIndex = row * vPlane.bytesPerRow + col * vPlane.bytesPerPixel!;
        final int uIndex = row * uPlane.bytesPerRow + col * uPlane.bytesPerPixel!;
        nv21[destinationIndex++] = vPlane.bytes[vIndex];
        nv21[destinationIndex++] = uPlane.bytes[uIndex];
      }
    }
    return nv21;
  }
}