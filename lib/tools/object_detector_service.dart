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

  // 讓外部強制放棄目標
  void resetLock() {
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

    // ⭐️ 核心修正：避免「重複旋轉」陷阱
    // ML Kit 吐出來的 BoundingBox 已經是轉正的，X 跟 Y 不用再互換。
    // 我們只需要定義「轉正後」的畫布寬高是多少，用來做百分比除法即可。
    double domainWidth = imgWidth;
    double domainHeight = imgHeight;
    
    // 手機直拿時，感光元件通常是橫的 (90 或 270 度)
    if (rotationCompensation == 90 || rotationCompensation == 270) {
      domainWidth = imgHeight;   // 原本的短邊變成轉正後的寬
      domainHeight = imgWidth;   // 原本的長邊變成轉正後的高
    }

    // ⭐️ 史上最乾淨的座標轉換
    Offset transform(double rawPxX, double rawPxY) {
      double nx = rawPxX / domainWidth;
      double ny = rawPxY / domainHeight;

      // 只有前鏡頭需要左右鏡像翻轉
      if (camera.lensDirection == CameraLensDirection.front) {
        nx = 1.0 - nx;
      }
      return Offset(nx, ny);
    }

    // 收集所有框供 Debug 顯示
    List<Rect> allNormalizedRects = [];
    for (var obj in objects) {
      final r = obj.boundingBox;
      final p1 = transform(r.left, r.top);
      final p2 = transform(r.right, r.bottom);
      allNormalizedRects.add(Rect.fromPoints(p1, p2)); 
    }

    // --- 尋找與鎖定邏輯 ---
    DetectedObject? targetObject;
    
    // 1. 死死咬住舊目標
    if (_lockedCenterRaw != null) {
      double minDistance = double.infinity;
      for (var obj in objects) {
        final rect = obj.boundingBox;
        final cx = rect.left + (rect.width / 2);
        final cy = rect.top + (rect.height / 2);
        double distSq = pow(cx - _lockedCenterRaw!.dx, 2) + pow(cy - _lockedCenterRaw!.dy, 2).toDouble();

        if (distSq < minDistance && distSq < (domainWidth * domainWidth * 0.15)) { 
          minDistance = distSq;
          targetObject = obj;
        }
      }
    }

    // 2. 初次鎖定：嚴格挑選「最靠近畫面正中間」的物體
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
    }

    // 更新鎖定中心
    final rect = targetObject.boundingBox;
    final centerX = rect.left + (rect.width / 2);
    final centerY = rect.top + (rect.height / 2);
    _lockedCenterRaw = Offset(centerX, centerY);

    String detectedLabel = '鎖定目標';
    if (targetObject.labels.isNotEmpty) {
      detectedLabel = targetObject.labels.first.text;
    }

    final finalPos = transform(centerX, centerY);

    return DetectionResult(
      position: finalPos,
      label: detectedLabel,
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