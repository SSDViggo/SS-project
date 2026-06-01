  import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// 相機硬體控制服務 (供 AI Agent 調整拍攝參數)
class CameraSettingsService {
  
  /// 根據 AI 的建議套用相機設定
  /// 
  /// [controller] 正在運作中的 CameraController
  /// [evOffset] 曝光補償值 (例如 -1.0 到 1.0)
  /// [flashOn] 是否強制開啟閃光燈
  /// [sceneMode] 場景描述，用於 UI 提示 (例如 "夜景模式", "逆光人像")
  Future<void> applyAISettings({
    required CameraController? controller,
    required double evOffset,
    required bool flashOn,
    required String sceneMode,
    required BuildContext context,
  }) async {
    // 確保相機已經初始化
    if (controller == null || !controller.value.isInitialized) return;

    try {
      // 1. 設定曝光補償 (Exposure Compensation)
      // 必須先取得硬體支援的極限值，避免設定超出範圍導致 Crash
      final minExposure = await controller.getMinExposureOffset();
      final maxExposure = await controller.getMaxExposureOffset();
      final clampedEv = evOffset.clamp(minExposure, maxExposure);
      
      await controller.setExposureOffset(clampedEv);

      // 2. 設定閃光燈 (Flash Mode)
      final flashMode = flashOn ? FlashMode.always : FlashMode.off;
      await controller.setFlashMode(flashMode);

      // 3. UI 視覺回饋：讓使用者知道 AI 改變了什麼
      if (context.mounted) {
        _showOptimizationToast(context, sceneMode, clampedEv, flashOn);
      }
      
    } catch (e) {
      debugPrint("CameraSettingsService Error: 無法套用相機參數 $e");
    }
  }

  /// 顯示 AI 最佳化完成的 UI 提示
  void _showOptimizationToast(BuildContext context, String scene, double ev, bool flash) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI 自動最佳化：$scene', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('曝光: ${ev > 0 ? '+' : ''}${ev.toStringAsFixed(1)} | 閃光燈: ${flash ? "開" : "關"}'),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E).withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}