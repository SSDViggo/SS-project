import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// 給[compute]使用的參數打包
class ImageProcessingParams {
  final Uint8List bytes;
  final double brightness;
  final double contrast;
  final double saturation;
  final double sharpness;

  ImageProcessingParams({
    required this.bytes,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.sharpness,
  });
}

/// 給[compute]呼叫的頂層函式，丟到背景執行緒避免UI卡頓
Uint8List processImageBytes(ImageProcessingParams params) {
  return ImageProcessingService().apply(
    params.bytes,
    brightness: params.brightness,
    contrast: params.contrast,
    saturation: params.saturation,
    sharpness: params.sharpness,
  );
}

/// 將亮度/對比度/飽和度/銳度（皆-100~100）套用到圖片的實際pixel資料，
/// 回傳處理後的JPEG bytes。
///
/// 亮度/對比度/飽和度的矩陣公式與[EditScreen]預覽用的[ColorFilter.matrix]一致，
/// 確保「看到的」跟「存下來的」效果相同。
class ImageProcessingService {
  Uint8List apply(
    Uint8List input, {
    required double brightness,
    required double contrast,
    required double saturation,
    required double sharpness,
  }) {
    img.Image image = img.decodeImage(input)!;

    if (brightness != 0 || contrast != 0 || saturation != 0) {
      final brightnessOffset = (brightness / 100) * 255;
      final contrastFactor = (1 + contrast / 100).clamp(0.0, 3.0);
      final sat = (1 + saturation / 100).clamp(0.0, 2.0);
      const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
      final invSat = 1 - sat;
      final translate = 128 * (1 - contrastFactor) + brightnessOffset;

      for (final pixel in image) {
        final r = pixel.r, g = pixel.g, b = pixel.b;
        pixel.r = (((lumR * invSat + sat) * r + (lumG * invSat) * g + (lumB * invSat) * b) * contrastFactor + translate)
            .clamp(0, 255);
        pixel.g = (((lumR * invSat) * r + (lumG * invSat + sat) * g + (lumB * invSat) * b) * contrastFactor + translate)
            .clamp(0, 255);
        pixel.b = (((lumR * invSat) * r + (lumG * invSat) * g + (lumB * invSat + sat) * b) * contrastFactor + translate)
            .clamp(0, 255);
      }
    }

    if (sharpness > 0) {
      final amount = sharpness / 100;
      image = img.convolution(
        image,
        filter: [0, -amount, 0, -amount, 1 + 4 * amount, -amount, 0, -amount, 0],
      );
    } else if (sharpness < 0) {
      final radius = (1 + (-sharpness / 100) * 4).round();
      image = img.gaussianBlur(image, radius: radius);
    }

    return img.encodeJpg(image, quality: 90);
  }
}