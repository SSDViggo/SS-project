import 'dart:math';
import 'package:flutter/material.dart';

/// AI 構圖指引覆蓋層 (加入遊戲化對齊解鎖特效)
class AIGuidanceOverlay extends StatelessWidget {
  final bool isVisible;
  final Offset subjectPosition;
  final Offset bestPosition;
  
  // ⭐️ 1. 新增缺少的參數
  final String subjectLabel;
  final bool showSubjectAndArrow;

  const AIGuidanceOverlay({
    super.key,
    this.isVisible = true,
    required this.subjectPosition,
    required this.bestPosition,
    this.subjectLabel = '主題位置',       // 給予預設值
    this.showSubjectAndArrow = true, // 給予預設值
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    // ⭐️ 2. 計算主體與目標位置的距離平方
    final distanceSq = pow(bestPosition.dx - subjectPosition.dx, 2) + pow(bestPosition.dy - subjectPosition.dy, 2);
    
    // ⭐️ 3. 判定是否「完美對齊」 (誤差半徑可視需求微調，這裡設定約 3000)
    final isAligned = distanceSq < 3000; 
    
    // ⭐️ 4. 定義狀態顏色：對齊時變成綠色，未對齊時保持藍/黃
    final targetColor = isAligned ? const Color(0xFF4CAF50) : const Color(0xFF0A58F5); 
    final subjectColor = isAligned ? const Color(0xFF4CAF50) : const Color(0xFFD4A000); 

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _AIGuidancePainter(
            subjectPos: subjectPosition,
            bestPos: bestPosition,
            showSubjectAndArrow: showSubjectAndArrow, // 傳遞給 Painter
            isAligned: isAligned,
            targetColor: targetColor,
            subjectColor: subjectColor,
          ),
          size: Size.infinite,
        ),
        
        // 目標位置 (藍/綠色標籤)
        Positioned(
          top: bestPosition.dy - 40,
          left: bestPosition.dx + 20,
          child: AITag(
            icon: isAligned ? Icons.check_circle : Icons.gps_fixed,
            label: isAligned ? '完美構圖！' : '最佳位置',
            color: targetColor,
          ),
        ),
        
        // 主題位置 (黃/綠色標籤) - 根據開關決定是否顯示
        if (showSubjectAndArrow)
          Positioned(
            top: subjectPosition.dy + 80,
            left: subjectPosition.dx - 45,
            child: AITag(
              icon: Icons.camera_enhance,
              label: subjectLabel,
              color: subjectColor, 
            ),
          ),
      ],
    );
  }
}

class _AIGuidancePainter extends CustomPainter {
  final Offset subjectPos;
  final Offset bestPos;
  final bool showSubjectAndArrow;
  final bool isAligned;
  final Color targetColor;
  final Color subjectColor;

  _AIGuidancePainter({
    required this.subjectPos, 
    required this.bestPos,
    required this.showSubjectAndArrow,
    required this.isAligned,
    required this.targetColor,
    required this.subjectColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 繪製目標虛線圈 (永遠顯示)
    final targetPaint = Paint()
      ..color = targetColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAligned ? 4.0 : 2.0; // 對齊時線條加粗
    canvas.drawCircle(bestPos, 60, targetPaint);

    if (!showSubjectAndArrow) return;

    // 2. 繪製主體對焦框
    final subPaint = Paint()
      ..color = subjectColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAligned ? 4.0 : 2.0;
    
    canvas.drawCircle(subjectPos, 70, subPaint);
    canvas.drawLine(Offset(subjectPos.dx, subjectPos.dy - 80), Offset(subjectPos.dx, subjectPos.dy + 80), subPaint);
    canvas.drawLine(Offset(subjectPos.dx - 80, subjectPos.dy), Offset(subjectPos.dx + 80, subjectPos.dy), subPaint);

    // 3. 繪製引導藍色箭頭 (只有在「未對齊」時才畫箭頭，對齊後隱藏)
    if (!isAligned) {
      final arrowPaint = Paint()
        ..color = targetColor.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      // 避免圈圈重疊時畫出太短的箭頭
      final distanceSq = pow(bestPos.dx - subjectPos.dx, 2) + pow(bestPos.dy - subjectPos.dy, 2);
      if (distanceSq > 10000) {  
        canvas.drawLine(subjectPos, Offset(bestPos.dx + 20, bestPos.dy + 20), arrowPaint);
        
        final arrowHead = Path()
          ..moveTo(bestPos.dx + 20, bestPos.dy + 20)
          ..lineTo(bestPos.dx + 40, bestPos.dy + 20)
          ..lineTo(bestPos.dx + 25, bestPos.dy + 40)
          ..close();
        canvas.drawPath(arrowHead, Paint()..color = targetColor.withOpacity(0.8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AIGuidancePainter oldDelegate) {
    return oldDelegate.subjectPos != subjectPos || 
           oldDelegate.bestPos != bestPos ||
           oldDelegate.showSubjectAndArrow != showSubjectAndArrow ||
           oldDelegate.isAligned != isAligned;
  }
}

/// 共用的 AI 標籤小工具 (保持不變)
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