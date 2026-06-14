import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class DetectionResult {
  final Offset position;
  final String label;
  final List<Rect> allRects;

  DetectionResult({required this.position, required this.label, required this.allRects});
}

class ObjectDetectorService {
  late ObjectDetector _objectDetector;
  bool _isInitialized = false;
  
  // 改用 Tracking ID 來死死咬住目標
  int? _lockedTrackingId; 
  // 儲存 Gemini 傳來的精準標籤
  String _targetLabel = '尋找目標中...'; 

  // EMA 平滑追蹤狀態
  double? _smoothedX;
  double? _smoothedY;
  final double _alpha = 0.25; // 平滑係數：數值越小越滑順，但也越遲鈍

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

  // 清除鎖定狀態
  void resetLock() {
    _lockedTrackingId = null;
    _targetLabel = '尋找目標中...';
    _smoothedX = null;
    _smoothedY = null;
  }

  // ⭐️ 新增：讓外部 (Gemini) 告訴 Service 目標叫什麼名字
  void updateTargetLabel(String label) {
    _targetLabel = label;
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
      // 畫面中完全沒東西時，不要馬上解除鎖定，可以容忍短暫丟失
      return null;
    }

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

    List<Rect> allNormalizedRects = [];
    for (var obj in objects) {
      final r = obj.boundingBox;
      allNormalizedRects.add(Rect.fromPoints(
        transform(r.left, r.top), 
        transform(r.right, r.bottom)
      )); 
    }

    // --- 尋找與鎖定邏輯 ---
    DetectedObject? targetObject;
    
    // 1. 優先透過 Tracking ID 尋找舊目標 (無視距離，死死咬住)
    if (_lockedTrackingId != null) {
      try {
        targetObject = objects.firstWhere((obj) => obj.trackingId == _lockedTrackingId);
      } catch (_) {
        // 在這幀丟失了該 ID，保持 targetObject 為 null
      }
    }

    // 2. 初次鎖定，或目標丟失時：挑選最靠近畫面正中間的物體重新鎖定
    if (targetObject == null) {
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
      targetObject ??= objects.first;
      
      // 更新追蹤 ID
      _lockedTrackingId = targetObject.trackingId;
    }

    // --- 計算座標與 EMA 平滑化 ---
    final rect = targetObject.boundingBox;
    final centerX = rect.left + (rect.width / 2);
    final centerY = rect.top + (rect.height / 2);
    final rawPos = transform(centerX, centerY);

    if (_smoothedX == null || _smoothedY == null) {
      // 第一次抓到，直接賦值
      _smoothedX = rawPos.dx;
      _smoothedY = rawPos.dy;
    } else {
      // 套用 EMA 平滑演算法
      _smoothedX = _alpha * rawPos.dx + (1 - _alpha) * _smoothedX!;
      _smoothedY = _alpha * rawPos.dy + (1 - _alpha) * _smoothedY!;
    }

    // 如果 Gemini 還沒給標籤，就先用 ML Kit 內建的擋一下
    String displayLabel = _targetLabel;
    if (_targetLabel == '尋找目標中...' && targetObject.labels.isNotEmpty) {
      displayLabel = targetObject.labels.first.text;
    }

    return DetectionResult(
      position: Offset(_smoothedX!, _smoothedY!),
      label: displayLabel,
      allRects: allNormalizedRects,
    );
  }
  // 內部工具：_inputImageFromCameraImage 保持不變
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
      nv21.setRange(
        destinationIndex,
        destinationIndex + width,
        yPlane.bytes,
        rowStart,
      );
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