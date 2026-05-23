import 'package:flutter/material.dart';

/// AI 構圖指引覆蓋層
class AIGuidanceOverlay extends StatelessWidget {
  final bool isVisible;
  final Offset subjectPosition;
  final Offset bestPosition;

  const AIGuidanceOverlay({
    super.key,
    this.isVisible = true,
    required this.subjectPosition,
    required this.bestPosition,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 繪製幾何圖形 (十字、圓圈、箭頭)
        CustomPaint(
          painter: _AIGuidancePainter(
            subjectPos: subjectPosition,
            bestPos: bestPosition,
          ),
          size: Size.infinite,
        ),
        
        // 2. 最佳位置 (藍色標籤) - 自動定位在藍圈右上方
        Positioned(
          top: bestPosition.dy - 40,
          left: bestPosition.dx + 20,
          child: const AITag(
            icon: Icons.gps_fixed,
            label: '最佳位置',
            color: Color(0xFF0A58F5),
          ),
        ),
        
        // 3. 主題位置 (黃色標籤) - 自動定位在黃圈正下方
        Positioned(
          top: subjectPosition.dy + 80,
          left: subjectPosition.dx - 45,
          child: const AITag(
            icon: Icons.camera_enhance,
            label: '主題位置',
            color: Color(0xFFD4A000), // 暗黃色
          ),
        ),
      ],
    );
  }
}

class _AIGuidancePainter extends CustomPainter {
  final Offset subjectPos;
  final Offset bestPos;

  _AIGuidancePainter({required this.subjectPos, required this.bestPos});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 繪製藍色虛線圈 (最佳位置)
    final bluePaint = Paint()
      ..color = const Color(0xFF0A58F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(bestPos, 60, bluePaint);

    // 2. 繪製黃色對焦框 (當前主題)
    final yellowPaint = Paint()
      ..color = const Color(0xFFD4A000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(subjectPos, 70, yellowPaint);
    canvas.drawLine(Offset(subjectPos.dx, subjectPos.dy - 80), Offset(subjectPos.dx, subjectPos.dy + 80), yellowPaint);
    canvas.drawLine(Offset(subjectPos.dx - 80, subjectPos.dy), Offset(subjectPos.dx + 80, subjectPos.dy), yellowPaint);

    // 3. 繪製引導藍色箭頭 (從主題指向最佳位置)
    final arrowPaint = Paint()
      ..color = const Color(0xFF0A58F5).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // 計算箭頭終點 (為了不畫進藍圈內，稍微偏移)
    final dx = bestPos.dx - subjectPos.dx;
    final dy = bestPos.dy - subjectPos.dy;
    final distance = (dx * dx + dy * dy); 
    // 簡單防呆，避免重疊時畫出奇怪的箭頭
    if (distance > 10000) { 
      canvas.drawLine(subjectPos, Offset(bestPos.dx + 20, bestPos.dy + 20), arrowPaint);
      
      final arrowHead = Path()
        ..moveTo(bestPos.dx + 20, bestPos.dy + 20)
        ..lineTo(bestPos.dx + 40, bestPos.dy + 20)
        ..lineTo(bestPos.dx + 25, bestPos.dy + 40)
        ..close();
      canvas.drawPath(arrowHead, Paint()..color = const Color(0xFF0A58F5).withOpacity(0.8));
    }
  }

  @override
  // 當座標改變時需要重新繪製
  bool shouldRepaint(covariant _AIGuidancePainter oldDelegate) {
    return oldDelegate.subjectPos != subjectPos || oldDelegate.bestPos != bestPos;
  }
}

/// 共用的 AI 標籤小工具
class AITag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const AITag({super.key, required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}