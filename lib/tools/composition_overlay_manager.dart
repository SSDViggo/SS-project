import 'package:flutter/material.dart';

import 'diagonal_lines_grid.dart'; 
import 'rule_of_thirds_grid.dart';

/// 構圖網格管理器 (供 AI Agent 動態切換構圖線使用)
class CompositionOverlayManager extends StatelessWidget {
  /// 支援的 pattern: 對應 Prompt 中的所有 Tool_ID
  final String patternType;
  final bool isVisible;

  const CompositionOverlayManager({
    super.key,
    this.patternType = 'none',
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible || patternType == 'none') return const SizedBox.shrink();

    // ⭐️ 1. 已經獨立成 Widget 的高階構圖輔助線
    if (patternType == 'Portrait_RuleOfThirds' || patternType == 'Landscape_RuleOfThirds') {
      return const RuleOfThirdsGrid();
    }
    
    if (patternType == 'Food_Diagonal' || patternType == 'Landscape_LeadingLines') {
      return const DiagonalLinesGrid();
    }

    // ⭐️ 2. 基礎幾何線，交由 CustomPainter 動態繪製
    return CustomPaint(
      painter: _CompositionPainter(patternType: patternType),
      size: Size.infinite,
    );
  }
}

class _CompositionPainter extends CustomPainter {
  final String patternType;

  _CompositionPainter({required this.patternType});

  @override
  void paint(Canvas canvas, Size size) {
    // 設定輔助線的樣式 (半透明白線)
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 根據 AI 回傳的 Tool_ID 畫出對應的線條
    switch (patternType) {
      case 'Food_Centered':
      case 'Landscape_Symmetry':
      case 'Food_FlatLay':
        _drawSymmetry(canvas, size, paint);
        break;
      case 'Portrait_Framing':
        _drawFraming(canvas, size, paint);
        break;
      case 'Portrait_NegativeSpace':
        _drawNegativeSpace(canvas, size, paint);
        break;
      default:
        break;
    }
  }

  /// 中心對稱十字線 (對應 Food_Centered, Landscape_Symmetry, Food_FlatLay)
  void _drawSymmetry(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
  }

  /// 框架構圖 (對應 Portrait_Framing) - 畫一個距離邊緣內縮的方框
  void _drawFraming(Canvas canvas, Size size, Paint paint) {
    final rect = Rect.fromLTWH(
      size.width * 0.15, size.height * 0.15,
      size.width * 0.7, size.height * 0.7
    );
    canvas.drawRect(rect, paint);
  }

  /// 留白構圖 (對應 Portrait_NegativeSpace) - 畫出兩條垂直分割線提示左右區域
  void _drawNegativeSpace(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter oldDelegate) {
    return oldDelegate.patternType != patternType;
  }
}