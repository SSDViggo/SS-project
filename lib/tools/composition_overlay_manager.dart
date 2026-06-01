import 'package:flutter/material.dart';

/// 構圖網格管理器 (供 AI Agent 動態切換構圖線使用)
class CompositionOverlayManager extends StatelessWidget {
  /// 支援的 pattern: 'rule_of_thirds', 's_curve', 'triangle', 'symmetry', 'none'
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

    switch (patternType) {
      case 'rule_of_thirds':
        _drawRuleOfThirds(canvas, size, paint);
        break;
      case 's_curve':
        _drawSCurve(canvas, size, paint);
        break;
      case 'triangle':
        _drawTriangle(canvas, size, paint);
        break;
      case 'symmetry':
        _drawSymmetry(canvas, size, paint);
        break;
      default:
        break;
    }
  }

  void _drawRuleOfThirds(Canvas canvas, Size size, Paint paint) {
    double stepX = size.width / 3;
    double stepY = size.height / 3;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(Offset(stepX * i, 0), Offset(stepX * i, size.height), paint);
      canvas.drawLine(Offset(0, stepY * i), Offset(size.width, stepY * i), paint);
    }
  }

  void _drawSCurve(Canvas canvas, Size size, Paint paint) {
    // 繪製一條從左下到右上的 S 型貝茲曲線 (Bezier Curve)
    final path = Path();
    path.moveTo(size.width * 0.1, size.height * 0.9);
    path.cubicTo(
      size.width * 0.8, size.height * 0.7, // 控制點 1
      size.width * 0.2, size.height * 0.3, // 控制點 2
      size.width * 0.9, size.height * 0.1, // 終點
    );
    canvas.drawPath(path, paint);
  }

  void _drawTriangle(Canvas canvas, Size size, Paint paint) {
    // 繪製正三角形構圖輔助線
    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.2); // 頂點
    path.lineTo(size.width * 0.1, size.height * 0.8); // 左下
    path.lineTo(size.width * 0.9, size.height * 0.8); // 右下
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSymmetry(Canvas canvas, Size size, Paint paint) {
    // 繪製中心十字對稱線
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter oldDelegate) {
    return oldDelegate.patternType != patternType;
  }
}