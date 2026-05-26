import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

/// 負責處理 Object Detection 的獨立 Service
class ObjectDetectorService {
  late ObjectDetector _objectDetector;
  bool _isInitialized = false;

  // 初始化 Detector
  void initialize() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: false, // 為了提升處理速度，不進行類別辨識，只抓 Bounding Box
      multipleObjects: false, // 只需要抓出畫面中最主要的一個 Subject
    );
    _objectDetector = ObjectDetector(options: options);
    _isInitialized = true;
  }

  // 釋放資源
  void dispose() {
    if (_isInitialized) {
      _objectDetector.close();
      _isInitialized = false;
    }
  }

  /// 處理 CameraImage 並回傳正規化 (0.0 ~ 1.0) 的中心點座標
  Future<Offset?> detectMainSubject({
    required CameraImage image,
    required CameraDescription camera,
    required Orientation deviceOrientation,
  }) async {
    if (!_isInitialized) return null;

    // 1. 將相機的 Stream 影像轉為 ML Kit 的格式
    final inputImage = _inputImageFromCameraImage(image, camera);
    if (inputImage == null) return null;

    // 2. 進行物件偵測
    // 正確的寫法
    final List<DetectedObject> objects = await _objectDetector.processImage(inputImage);

    // 如果沒有抓到物件，回傳 null
    if (objects.isEmpty) return null;

    // 3. 計算並正規化座標
    final mainObject = objects.first;
    final rect = mainObject.boundingBox;

    final imgWidth = image.width.toDouble();
    final imgHeight = image.height.toDouble();

    final centerX = rect.left + (rect.width / 2);
    final centerY = rect.top + (rect.height / 2);

    double normalizedX = centerX / imgWidth;
    double normalizedY = centerY / imgHeight;

    // 處理 Portrait 方向的維度互換 (針對 Android 設備常見的 Sensor 特性)
    if (deviceOrientation == Orientation.portrait && Platform.isAndroid) {
      normalizedX = centerY / imgHeight;
      normalizedY = centerX / imgWidth;
    }

    return Offset(normalizedX, normalizedY);
  }
  /// 處理靜態檔案路徑 (供測試用)
  Future<Offset?> detectFromFilePath({
    required String filePath,
    required double imgWidth,
    required double imgHeight,
  }) async {
    if (!_isInitialized) return null;

    // 從檔案路徑建立 InputImage
    final inputImage = InputImage.fromFilePath(filePath);
    final List<DetectedObject> objects = await _objectDetector.processImage(inputImage);

    // 若沒有抓到物件，回傳 null
    if (objects.isEmpty) return null;

    final mainObject = objects.first;
    final rect = mainObject.boundingBox;

    // 計算 Bounding Box 的中心點
    final centerX = rect.left + (rect.width / 2);
    final centerY = rect.top + (rect.height / 2);

    // 進行 Normalization (正規化至 0.0 ~ 1.0)
    // 靜態圖片通常不需要處理複雜的 Sensor Orientation 翻轉
    return Offset(centerX / imgWidth, centerY / imgHeight);
  }
  /// 內部共用工具：負責處理複雜的影像格式轉換
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