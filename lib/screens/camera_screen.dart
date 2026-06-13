import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../tools/ai_guidance_overlay.dart';
import '../tools/object_detector_service.dart';
import '../tools/composition_overlay_manager.dart'; 
import '../tools/camera_settings_service.dart';

// ⭐️ 1. 定義我們設計的四大狀態機
enum CameraWorkflow {
  live,         // 正常即時預覽
  analyzing,    // 畫面凍結，等待 Gemini 分析中
  magicMoment,  // 凍結展示：Gemini 回傳結果，顯示目標與主體
  guiding       // 遊戲化引導：畫面解凍，讓使用者對齊
}

class FullScreenCameraScreen extends StatefulWidget {
  final CameraController? cameraController;

  const FullScreenCameraScreen({super.key, this.cameraController});

  @override
  State<FullScreenCameraScreen> createState() => _FullScreenCameraScreenState();
}

class _FullScreenCameraScreenState extends State<FullScreenCameraScreen> {
  File? _testImageFile;
  
  // ⭐️ 2. 替換原本單純的 _hasGuidance，改用狀態機控制
  CameraWorkflow _workflow = CameraWorkflow.live;
  String _subjectLabel = '分析中...'; // 儲存 LLM 辨識出的物體名稱

  bool _isProcessing = false; 
  String _currentComposition = 'none'; 
  final CameraSettingsService _cameraSettingsService = CameraSettingsService();
  final GlobalKey _previewKey = GlobalKey(); 
  
  late final GenerativeModel _geminiModel;

  double _subjectX = 0.5;
  double _subjectY = 0.5;
  double _bestX = 0.9;
  double _bestY = 0.66;

  List<Rect> _allDebugRects = [];
  final ObjectDetectorService _detectorService = ObjectDetectorService();

  @override
  void initState() {
    super.initState();
    _detectorService.initialize();
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      debugPrint('警告：找不到 API Key，請檢查 .env 檔案設定。');
    }
    _geminiModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
  }

  @override
  void dispose() {
    if (widget.cameraController?.value.isStreamingImages == true) {
      widget.cameraController?.stopImageStream();
    }
    _detectorService.dispose();
    super.dispose();
  }
  
  // ⭐️ 3. 核心魔法流程：Freeze & Guide
  Future<void> _captureAndAskGemini() async {
    // 只有在 live 狀態才能觸發分析
    if (_isProcessing || _workflow != CameraWorkflow.live) return;
    
    setState(() {
      _isProcessing = true;
      _workflow = CameraWorkflow.analyzing; // 進入分析中狀態
    });
    
    // ⭐️ 凍結相機預覽
    await widget.cameraController?.pausePreview();
    
    try {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0); 
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final prompt = TextPart('''
        You are a professional photography assistant. 
        Look at the attached camera preview image. The user's intended main subject is highlighted with a yellow marker.

        Please perform the following tasks:
        1. Identify the main subject.
        2. Analyze the scene to choose the BEST composition technique.
        3. Determine the ideal coordinates (x, y) for the subject (0.0 to 1.0).
        4. Decide if the exposure needs adjustment (-2.0 to 2.0) or if the flash is needed based on the lighting.

        You MUST respond ONLY with a valid JSON object:
        {
          "detected_subject": "string (Traditional Chinese, e.g. 咖啡杯, 人像)",
          "composition_technique": "string",
          "patternType": "string",
          "ideal_x": float,
          "ideal_y": float,
          "actionable_tip": "string",
          "ev_offset": float,
          "flash_on": boolean,
          "scene_mode": "string"
        }
      ''');
      final imagePart = DataPart('image/png', pngBytes);

      final response = await _geminiModel.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      if (!mounted) return;
      
      String responseText = response.text?.trim() ?? '';
      responseText = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(responseText);
      
      final double newBestX = data['ideal_x'].toDouble();
      final double newBestY = data['ideal_y'].toDouble();
      final String newPattern = data['patternType'] ?? 'none';
      final String detectedSubject = data['detected_subject'] ?? '目標物';

      // ⭐️ 進入 The Magic Moment：展示 Gemini 計算出的完美座標
      setState(() {
        _bestX = newBestX; 
        _bestY = newBestY;
        _currentComposition = newPattern;
        _subjectLabel = detectedSubject;
        _workflow = CameraWorkflow.magicMoment;
      });

      // 讓凍結的畫面停留 2.5 秒，給使用者時間吸收資訊
      await Future.delayed(const Duration(milliseconds: 2500));
      
      if (!mounted) return;
      
      // ⭐️ 解凍相機，進入遊戲化引導對齊階段
      await widget.cameraController?.resumePreview();
      
      setState(() {
        _workflow = CameraWorkflow.guiding;
      });

      // ⭐️ 啟動物件追蹤串流
      if (widget.cameraController != null && widget.cameraController!.value.isStreamingImages == false) {
        widget.cameraController?.startImageStream((image) {
          if (!_isProcessing) {
            _processCameraImage(image);
          }
        });
      }

    } catch (e) {
      debugPrint('Error: $e');
      await widget.cameraController?.resumePreview();
      setState(() => _workflow = CameraWorkflow.live);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分析失敗，已恢復預覽')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    _isProcessing = true;
    try {
      final result = await _detectorService.detectMainSubject(
        image: image,
        camera: widget.cameraController!.description,
        deviceOrientation: MediaQuery.of(context).orientation,
      );

      if (result != null) {
        setState(() {
          _subjectX = result.position.dx;
          _subjectY = result.position.dy;
          _allDebugRects = result.allRects;
        });
      }
    } catch (e) {
      debugPrint("Object Detection Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  // ... (_runStaticImageTest 保持不變，若不需要可刪除) ...
  void _runStaticImageTest() {}

  @override
  Widget build(BuildContext context) {  
    final screenSize = MediaQuery.of(context).size;
    final aiBestPos = Offset(screenSize.width * _bestX, screenSize.height * _bestY);
    final aiSubjectPos = Offset(screenSize.width * _subjectX, screenSize.height * _subjectY);

    // 判斷是否要顯示 UI 指引
    final showGuidance = _workflow == CameraWorkflow.magicMoment || _workflow == CameraWorkflow.guiding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: _previewKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.cameraController != null && widget.cameraController!.value.isInitialized)
                  CameraPreview(widget.cameraController!)
                else
                  const Center(child: Text('Camera Preview', style: TextStyle(color: Colors.white54))),
                
                CompositionOverlayManager(
                  isVisible: showGuidance,
                  patternType: _currentComposition,
                ),
                
                // ⭐️ 導入對齊遊戲 UI
                AIGuidanceOverlay(
                  isVisible: showGuidance,
                  subjectPosition: aiSubjectPos,
                  bestPosition: aiBestPos,
                  subjectLabel: _subjectLabel,
                  // 不論是魔法時刻還是引導階段，都顯示黃圈跟箭頭
                  debugRects: _allDebugRects,
                  showSubjectAndArrow: true, 
                ),

                // ⭐️ 遮罩：當 AI 正在思考時，讓畫面變暗並顯示 Loading
                if (_workflow == CameraWorkflow.analyzing)
                  Container(
                    color: Colors.black.withOpacity(0.4),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // ⭐️ 引導提示詞：解凍後出現在畫面上方
          if (_workflow == CameraWorkflow.guiding)
            Positioned(
              top: 100,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF0A58F5), width: 1.5)
                  ),
                  child: Text(
                    '請移動手機，將 [$_subjectLabel] 對準藍色光圈',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTopBar(context),
                _buildBottomControls(context),
              ],
            ),
          ),
        ],
      ),
      // ... bottomNavigationBar 保持不變 ...
    );
  }

 Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ⭐️ 左側關閉按鈕，加上半透明黑色圓底
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4), // 淡淡的黑色背景，數字可調整透明度
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Row(
            children: [
              // ⭐️ 右側對焦按鈕，加上半透明黑色圓底
              // Container(
              //   decoration: BoxDecoration(
              //     color: Colors.black.withOpacity(0.4), // 淡淡的黑色背景
              //     shape: BoxShape.circle,
              //   ),
              //   child: IconButton(
              //     icon: Icon(
              //       Icons.center_focus_strong,
              //       // 根據是否有開起追蹤串流來亮燈
              //       color: widget.cameraController?.value.isStreamingImages == true 
              //           ? const Color(0xFF0A58F5) 
              //           : Colors.white,
              //     ),
              //     onPressed: _toggleLiveDetection,
              //   ),
              // ),
              // 如果你之後有把閃光燈或翻轉鏡頭加回來，也可以用同樣的 Container 包住它們
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 24, right: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 重置按鈕 (可讓使用者隨時跳出引導流程回到預覽)
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              if (widget.cameraController?.value.isStreamingImages == true) {
                widget.cameraController?.stopImageStream();
              }
              _detectorService.resetLock();
              setState(() {
                _workflow = CameraWorkflow.live;
                _currentComposition = 'none';
                _allDebugRects = [];
              });
            },
          ),
          
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(color: Color(0xFF0A58F5), shape: BoxShape.circle),
                child: const Icon(Icons.camera, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 8),
            ],
          ),
          
          // AI 分析按鈕
          IconButton(
            icon: _workflow == CameraWorkflow.analyzing 
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(color: Color(0xFF0A58F5), strokeWidth: 2.0),
                  )
                : const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
            onPressed: _captureAndAskGemini, 
          ),
        ],
      ),
    );
  }
}