import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

/// 將回傳結果包裝成 Class，同時包含座標與 Label
class DetectionResult {
  final Offset position;
  final String label;

  DetectionResult({required this.position, required this.label});
}

class ObjectDetectorService {
  late ObjectDetector _objectDetector;
  bool _isInitialized = false;

  // ⭐️ 核心狀態：紀錄上一幀的中心座標，用來做 Euclidean distance 追蹤
  Offset? _lockedCenterRaw; 

  void initialize() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,  // 盡量分類出 Label
      multipleObjects: true,  // ⭐️ 必須為 true，避免主體被背景高對比物體搶走
    );

    _objectDetector = ObjectDetector(options: options);
    _isInitialized = true;
  }

  void dispose() {
    if (_isInitialized) {
      _objectDetector.close();
      _isInitialized = false;
    }
    _lockedCenterRaw = null;
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

    // 若畫面沒東西，解除鎖定狀態
    if (objects.isEmpty) {
      _lockedCenterRaw = null;
      return null;
    }

    DetectedObject? targetObject;
    final imgWidth = image.width.toDouble();
    final imgHeight = image.height.toDouble();

    // ⭐️ 1. Centroid Tracking: 尋找距離上一幀「鎖定中心」最近的物體
    if (_lockedCenterRaw != null) {
      double minDistance = double.infinity;
      
      for (var obj in objects) {
        final rect = obj.boundingBox;
        final cx = rect.left + (rect.width / 2);
        final cy = rect.top + (rect.height / 2);
        
        // 計算中心點距離的平方
        double distSq = pow(cx - _lockedCenterRaw!.dx, 2) + pow(cy - _lockedCenterRaw!.dy, 2).toDouble();

        // 容錯範圍：如果不超過畫面寬度比例的 15%，就認定是同一個追蹤目標
        if (distSq < minDistance && distSq < (imgWidth * imgWidth * 0.15)) { 
          minDistance = distSq;
          targetObject = obj;
        }
      }
    }

    // ⭐️ 2. 如果跟丟了 (或第一次偵測)，重新挑選 Bounding Box 面積最大的物體
    if (targetObject == null) {
      double maxArea = 0;
      for (var obj in objects) {
        final rect = obj.boundingBox;
        final area = rect.width * rect.height;
        if (area > maxArea) {
          maxArea = area;
          targetObject = obj;
        }
      }
      targetObject ??= objects.first;
    }

    // 3. 更新鎖定狀態 (紀錄新的中心點)
    final rect = targetObject.boundingBox;
    final centerX = rect.left + (rect.width / 2);
    final centerY = rect.top + (rect.height / 2);
    _lockedCenterRaw = Offset(centerX, centerY);

    // 4. 處理 Label (若 ML Kit 認不出分類，給予預設文字)
    String detectedLabel = '鎖定目標';
    if (targetObject.labels.isNotEmpty) {
      detectedLabel = targetObject.labels.first.text;
    }

    // 5. Normalization (將座標轉換為 0.0 ~ 1.0)
    double rawX = centerX / imgWidth;
    double rawY = centerY / imgHeight;

    double normalizedX = rawX;
    double normalizedY = rawY;

    // 6. 處理 Orientation 與鏡像 (Mirroring)
    if (deviceOrientation == Orientation.portrait) {
      normalizedX = rawY;
      normalizedY = rawX;

      if (Platform.isAndroid) {
        if (camera.lensDirection == CameraLensDirection.front) {
          normalizedX = 1.0 - normalizedX;
          normalizedY = 1.0 - normalizedY;
        } else {
          normalizedX = 1.0 - normalizedX; 
        }
      } else if (Platform.isIOS) {
        if (camera.lensDirection == CameraLensDirection.front) {
          normalizedX = 1.0 - normalizedX;
        }
      }
    } else {
      if (camera.lensDirection == CameraLensDirection.front) {
        normalizedX = 1.0 - normalizedX;
      }
    }

    return DetectionResult(
      position: Offset(normalizedX, normalizedY),
      label: detectedLabel,
    );
  }

  // 以下 _inputImageFromCameraImage 保持不變
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

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) &&
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }
}