import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

/// ObjectDetectorService
///
/// 簡單封裝 ML Kit 的物件偵測功能，提供：
/// - `initialize()` / `dispose()` 管理生命週期
/// - `detectMainSubject(...)`：接收相機串流的 `CameraImage`，回傳主體的正規化中心座標（Offset，x/y 範圍 0.0~1.0）
/// - `detectFromFilePath(...)`：以靜態圖片路徑做測試用偵測
///
/// 備註：座標系為圖片像素座標，回傳前會做簡單的 orientation 處理（針對常見 Android/iOS 差異）。
class ObjectDetectorService {
  late ObjectDetector _objectDetector;
  bool _isInitialized = false;

  /// 初始化物件偵測器。
  ///
  /// 使用 `DetectionMode.stream` 以便於相機串流即時偵測。
  void initialize() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: false, // 不做分類以提高效能
      multipleObjects: false, // 只取畫面中最主要的一個物件
    );

    _objectDetector = ObjectDetector(options: options);
    _isInitialized = true;
  }

  /// 釋放底層資源
  void dispose() {
    if (_isInitialized) {
      _objectDetector.close();
      _isInitialized = false;
    }
  }

  /// 偵測相機串流影格中的主體，並回傳正規化的中心點座標 (x, y 為 0.0 ~ 1.0)
  ///
  /// 參數：
  /// - `image`: 相機提供的 `CameraImage`
  /// - `camera`: 相機描述物件，用來取得 sensorOrientation 與前/後鏡頭資訊
  /// - `deviceOrientation`: 當前裝置方向（portrait / landscape），用來簡單調整座標
  Future<Offset?> detectMainSubject({
    required CameraImage image,
    required CameraDescription camera,
    required Orientation deviceOrientation,
  }) async {
    if (!_isInitialized) return null;

    // 1) 將 CameraImage 轉為 ML Kit 可接受的 InputImage
    final inputImage = _inputImageFromCameraImage(image, camera);
    if (inputImage == null) return null;

    // 2) 執行偵測
    final List<DetectedObject> objects = await _objectDetector.processImage(inputImage);

    if (objects.isEmpty) return null;

    // 3) 取第一個（最主要）物件，計算其 bounding box 中心並正規化
    final mainObject = objects.first;
    final rect = mainObject.boundingBox;

    final imgWidth = image.width.toDouble();
    final imgHeight = image.height.toDouble();

    final centerX = rect.left + (rect.width / 2);
    final centerY = rect.top + (rect.height / 2);

    double normalizedX = centerX / imgWidth;
    double normalizedY = centerY / imgHeight;

    // 裝置直式（portrait）在某些 Android 裝置 SensorOrientation 與像素維度會有互換，做簡單的調整
    if (deviceOrientation == Orientation.portrait && Platform.isAndroid) {
      normalizedX = centerY / imgHeight;
      normalizedY = centerX / imgWidth;
    }

    return Offset(normalizedX, normalizedY);
  }

  /// 針對靜態圖片的偵測（主要用於測試）
  ///
  /// 輸入需提供圖片的寬高（像素），回傳方式同上為正規化的中心座標
  /// 處理靜態檔案路徑 (供測試用)
  Future<Offset?> detectFromFilePath({
    required String filePath,
    required double imgWidth,
    required double imgHeight,
  }) async {
    // ⭐️ 關鍵修改：針對靜態圖片，即時建立一個專屬的 single 模式 Detector
    final staticOptions = ObjectDetectorOptions(
      mode: DetectionMode.single, // 改為單張圖片模式
      classifyObjects: false,
      multipleObjects: false,
    );
    final staticDetector = ObjectDetector(options: staticOptions);

    try {
      // 從檔案路徑建立 InputImage
      final inputImage = InputImage.fromFilePath(filePath);
      
      // 使用專屬的 staticDetector 進行辨識
      final List<DetectedObject> objects = await staticDetector.processImage(inputImage);

      // 若沒有抓到物件，回傳 null
      if (objects.isEmpty) return null;

      final mainObject = objects.first;
      final rect = mainObject.boundingBox;

      // 計算 Bounding Box 的中心點
      final centerX = rect.left + (rect.width / 2);
      final centerY = rect.top + (rect.height / 2);

      // 進行 Normalization (正規化至 0.0 ~ 1.0)
      return Offset(centerX / imgWidth, centerY / imgHeight);
      
    } finally {
      // ⭐️ 辨識完畢後，立刻釋放這個暫時的 Detector 資源
      staticDetector.close();
    }
  }
  /// 內部工具：將 CameraImage 轉成 ML Kit 的 InputImage
  ///
  /// 注意：不同平台與相機格式的支援度不同，若無法轉換則回傳 null。
  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    // 依據平台決定 rotation 的來源值
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      // Android 裝置的 rotation compensation 可能需要根據 lens direction 處理
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

    // 檢查是否為 ML Kit 支援的格式（此處以常見的 NV21 / BGRA8888 作為示範）
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