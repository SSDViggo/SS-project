import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class DetectionResult {
  final Offset position;
  final String label;

  DetectionResult({required this.position, required this.label});
}

class ObjectDetectorService {
  late ObjectDetector _objectDetector;
  bool _isInitialized = false;
  Offset? _lockedCenterRaw; 

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

    if (objects.isEmpty) {
      _lockedCenterRaw = null;
      return null;
    }

    DetectedObject? targetObject;
    final imgWidth = image.width.toDouble();
    final imgHeight = image.height.toDouble();

    // 1. 尋找距離上一幀「鎖定中心」最近的物體 (死死咬住目標)
    if (_lockedCenterRaw != null) {
      double minDistance = double.infinity;
      for (var obj in objects) {
        final rect = obj.boundingBox;
        final cx = rect.left + (rect.width / 2);
        final cy = rect.top + (rect.height / 2);
        double distSq = pow(cx - _lockedCenterRaw!.dx, 2) + pow(cy - _lockedCenterRaw!.dy, 2).toDouble();

        if (distSq < minDistance && distSq < (imgWidth * imgWidth * 0.15)) { 
          minDistance = distSq;
          targetObject = obj;
        }
      }
    }

    // 2. ⭐️ 強化版初次鎖定：綜合考量「最靠近畫面正中間」與「面積大小」
    // 這會解決它跑去抓邊緣巨大音箱的問題，優先鎖定你鏡頭正對著的物體！
    if (targetObject == null) {
      double bestScore = double.infinity;
      final centerImageX = imgWidth / 2;
      final centerImageY = imgHeight / 2;
      
      for (var obj in objects) {
        final rect = obj.boundingBox;
        final cx = rect.left + (rect.width / 2);
        final cy = rect.top + (rect.height / 2);
        final area = rect.width * rect.height;
        
        // 距離畫面中心的平方
        final distToCenterSq = pow(cx - centerImageX, 2) + pow(cy - centerImageY, 2).toDouble();
        
        // 核心邏輯：距離中心越近分數越低，面積越大分數越低 (找最低分者)
        final score = distToCenterSq / (area + 1);
        
        if (score < bestScore) {
          bestScore = score;
          targetObject = obj;
        }
      }
      targetObject ??= objects.first;
    }

    final rect = targetObject.boundingBox;
    final centerX = rect.left + (rect.width / 2);
    final centerY = rect.top + (rect.height / 2);
    _lockedCenterRaw = Offset(centerX, centerY);

    String detectedLabel = '鎖定目標';
    if (targetObject.labels.isNotEmpty) {
      detectedLabel = targetObject.labels.first.text;
    }

    // 3. ⭐️ 終極穩固座標轉換：放棄硬猜，直接讀取相機真實 Sensor 旋轉角度
    double rawX = centerX / imgWidth;
    double rawY = centerY / imgHeight;

    double normalizedX = rawX;
    double normalizedY = rawY;

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

    // 根據硬體回報的角度進行精確座標映射 (完美相容模擬器與各種怪異實機)
    switch (rotationCompensation) {
      case 90:
        normalizedX = 1.0 - rawY;
        normalizedY = rawX;
        break;
      case 270:
        normalizedX = rawY;
        normalizedY = 1.0 - rawX;
        break;
      case 180:
        normalizedX = 1.0 - rawX;
        normalizedY = 1.0 - rawY;
        break;
      case 0:
      default:
        normalizedX = rawX;
        normalizedY = rawY;
        break;
    }

    // 處理前鏡頭鏡像反轉
    if (camera.lensDirection == CameraLensDirection.front) {
      normalizedX = 1.0 - normalizedX;
    }

    return DetectionResult(
      position: Offset(normalizedX, normalizedY),
      label: detectedLabel,
    );
  }

  // 內部工具：將 CameraImage 轉成 ML Kit 的 InputImage (保持不變)
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