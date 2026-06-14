import 'package:flutter/material.dart';

/// 對角線與引導線構圖輔助 UI
/// 畫面上會呈現從四個角落交叉的對角線 (X 型)
class DiagonalLinesGrid extends StatelessWidget {
  const DiagonalLinesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 IgnorePointer 確保這些線條不會阻擋到下層的手勢操作 (如對焦、縮放)
    return IgnorePointer(
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: CustomPaint(
          painter: _DiagonalLinesPainter(),
        ),
      ),
    );
  }
}

class _DiagonalLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 設定畫筆樣式：白色、半透明、線條粗細為 1.5
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 1. 繪製左上到右下的對角線 (Leading Line / Baroque Diagonal)
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width, size.height),
      paint,
    );

    // 2. 繪製右上到左下的對角線 (Sinister Diagonal)
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(0, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) { 
    return false;
  }
}