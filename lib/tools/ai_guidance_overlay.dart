import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'gemini_composition_service.dart';

class AIGuidanceOverlay extends StatelessWidget {
  final bool isVisible;
  final Rect? currentRect; 
  final Rect? targetRect;  
  final String subjectLabel;
  final List<GuideLine>? guideLines;

  const AIGuidanceOverlay({
    super.key,
    required this.isVisible,
    this.currentRect,
    this.targetRect,
    this.subjectLabel = '',
    this.guideLines,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return CustomPaint(
      size: Size.infinite,
      painter: _BoxGuidancePainter(
        currentRect: currentRect,
        targetRect: targetRect,
        guideLines: guideLines,
      ),
    );
  }
}

class _BoxGuidancePainter extends CustomPainter {
  final Rect? currentRect;
  final Rect? targetRect;
  final List<GuideLine>? guideLines;

  _BoxGuidancePainter({
    this.currentRect, 
    this.targetRect, 
    this.guideLines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 黃色框 (現在位置)
    if (currentRect != null) {
      final yellowPaint = Paint()
        ..color = Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(currentRect!, yellowPaint);
    }

    // 藍色框 (目標位置)
    if (targetRect != null) {
      final bluePaint = Paint()
        ..color = const Color(0xFF0A58F5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRect(targetRect!, bluePaint);
    }

    // 構圖輔助線 (如延伸線)
    if (guideLines != null && guideLines!.isNotEmpty) {
      final guideLinePaint = Paint()
        ..color = Colors.greenAccent.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      for (var line in guideLines!) {
        // 將 0.0~1.0 的比例乘上螢幕寬高
        final p1 = Offset(line.start[0] * size.width, line.start[1] * size.height);
        final p2 = Offset(line.end[0] * size.width, line.end[1] * size.height);
        canvas.drawLine(p1, p2, guideLinePaint);
      }
    }

    // 位移箭頭
    if (currentRect != null && targetRect != null) {
      final arrowPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      final p1 = currentRect!.center;
      final p2 = targetRect!.center;

      canvas.drawLine(p1, p2, arrowPaint);

      // 畫出箭頭尖端 (利用簡單的三角函數計算角度)
      final dX = p2.dx - p1.dx;
      final dY = p2.dy - p1.dy;
      final angle = math.atan2(dY, dX);
      
      const arrowLength = 16.0; // 箭頭尖端長度
      const arrowAngle = math.pi / 6; // 30度角開口

      // 計算箭頭左右兩邊的頂點
      final tip1 = Offset(
        p2.dx - arrowLength * math.cos(angle - arrowAngle),
        p2.dy - arrowLength * math.sin(angle - arrowAngle),
      );
      final tip2 = Offset(
        p2.dx - arrowLength * math.cos(angle + arrowAngle),
        p2.dy - arrowLength * math.sin(angle + arrowAngle),
      );

      // 用 Path 畫出箭頭三角形並填滿
      final arrowHeadPath = Path()
        ..moveTo(p2.dx, p2.dy)
        ..lineTo(tip1.dx, tip1.dy)
        ..lineTo(tip2.dx, tip2.dy)
        ..close();

      canvas.drawPath(arrowHeadPath, Paint()..color = Colors.red..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxGuidancePainter oldDelegate) {
    return oldDelegate.currentRect != currentRect ||
           oldDelegate.targetRect != targetRect ||
           oldDelegate.guideLines != guideLines;
  }
}