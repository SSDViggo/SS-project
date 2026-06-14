import 'package:flutter/material.dart';

class RuleOfThirdsGrid extends StatelessWidget {
  const RuleOfThirdsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RuleOfThirdsPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _RuleOfThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ⭐️ 1. 底層陰影畫筆 (較粗的黑色半透明)
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0; // 比白線粗一點，製造邊框效果

    // ⭐️ 2. 表層主線畫筆 (把原本白色的 Opacity 提高，讓它更亮)
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.85) 
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0; // 保持細緻的專業感

    double stepX = size.width / 3;
    double stepY = size.height / 3;

    // 繪製垂直線
    for (int i = 1; i < 3; i++) {
      // 先畫黑線打底，再畫白線覆蓋
      canvas.drawLine(Offset(stepX * i, 0), Offset(stepX * i, size.height), shadowPaint);
      canvas.drawLine(Offset(stepX * i, 0), Offset(stepX * i, size.height), linePaint);
    }

    // 繪製水平線
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(Offset(0, stepY * i), Offset(size.width, stepY * i), shadowPaint);
      canvas.drawLine(Offset(0, stepY * i), Offset(size.width, stepY * i), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}