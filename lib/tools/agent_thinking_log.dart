import 'dart:async';
import 'package:flutter/material.dart';

class AgentThinkingLog extends StatefulWidget {
  final List<String> steps;
  final VoidCallback onComplete;

  const AgentThinkingLog({
    super.key,
    required this.steps,
    required this.onComplete,
  });

  @override
  State<AgentThinkingLog> createState() => _AgentThinkingLogState();
}

class _AgentThinkingLogState extends State<AgentThinkingLog> {
  String _displayedText = "";
  int _currentStepIndex = 0;
  int _currentCharIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    if (widget.steps.isEmpty) {
      widget.onComplete();
      return;
    }

    // 設定打字速度
    _timer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (_currentStepIndex >= widget.steps.length) {
        timer.cancel();
        // 全部印完後，停頓 1.5 秒讓使用者看完，再觸發下一步
        Future.delayed(const Duration(milliseconds: 1500), widget.onComplete);
        return;
      }

      final currentStepText = widget.steps[_currentStepIndex];

      if (_currentCharIndex < currentStepText.length) {
        setState(() {
          _displayedText += currentStepText[_currentCharIndex];
          _currentCharIndex++;
        });
      } else {
        // 印完一行，換行並稍微停頓再印下一行
        timer.cancel();
        setState(() {
          _displayedText += "\n\n";
        });
        _currentStepIndex++;
        _currentCharIndex = 0;
        Future.delayed(const Duration(milliseconds: 500), _startTyping);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0A58F5).withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A58F5).withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Text(
        _displayedText + (_timer?.isActive == true ? " ▋" : ""),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.6,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}