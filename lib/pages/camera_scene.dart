import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui; // 用於處理 Image
import 'package:flutter/rendering.dart'; // 為了使用 RenderRepaintBoundary

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 為了 rootBundle
import 'package:path_provider/path_provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// 工具模組：網格、AI 引導 overlay、以及物件偵測服務
import '../tools/ai_guidance_overlay.dart';
import '../tools/object_detector_service.dart';
import '../tools/composition_overlay_manager.dart'; 
import '../tools/camera_settings_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
/// 相機畫面（全螢幕）
///
/// - 顯示相機預覽或測試圖片
/// - 支援即時物件偵測與 AI 構圖建議 overlay
class FullScreenCameraScreen extends StatefulWidget {
  /// 傳入的相機控制器（由呼叫端建立並初始化）
  final CameraController? cameraController;

  const FullScreenCameraScreen({super.key, this.cameraController});

  @override
  State<FullScreenCameraScreen> createState() => _FullScreenCameraScreenState();
}

class _FullScreenCameraScreenState extends State<FullScreenCameraScreen> {
  File? _testImageFile;
  bool _hasGuidance = false;
  bool _isProcessing = false; 
  String _currentComposition = 'none'; // 預設不顯示特定幾何網格
  final CameraSettingsService _cameraSettingsService = CameraSettingsService();

  final GlobalKey _previewKey = GlobalKey(); 
  
  // 建立 Gemini Model (請替換為你的 API Key)
  late final GenerativeModel _geminiModel;

  double _subjectX = 0.5;
  double _subjectY = 0.5;
  double _bestX = 0.9;
  double _bestY = 0.66;

  final ObjectDetectorService _detectorService = ObjectDetectorService();

  @override
  void initState() {
    super.initState();
    // 初始化物件偵測 Service。如果需要可在此傳入模型或設定
    _detectorService.initialize();
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      debugPrint('警告：找不到 API Key，請檢查 .env 檔案設定。');
    }
    _geminiModel = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey, // 記得換成真實的 API Key
    );
  }

  @override
  void dispose() {
    widget.cameraController?.stopImageStream();
    _detectorService.dispose();
    super.dispose();
  }

  void _toggleLiveDetection() async {
    if (widget.cameraController == null || !widget.cameraController!.value.isInitialized) return;
    // 切換是否要顯示引導（同時啟/停相機影格串流）
    setState(() => _hasGuidance = !_hasGuidance);

    if (_hasGuidance) {
      // 啟動影格串流，回呼中只保留一個處理序列，避免重入
      await widget.cameraController!.startImageStream((CameraImage image) {
        if (_isProcessing) return;
        _processCameraImage(image);
      });
    } else {
      await widget.cameraController!.stopImageStream();
    }
  }

  Future<void> _captureAndAskGemini() async {
    if (_isProcessing) return;
    
    setState(() => _isProcessing = true);
    
    try {
      // 1. 透過 RepaintBoundary 取得當前畫面的截圖
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0); 
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // 2. 構建 Gemini Prompt
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
          "detected_subject": "string",
          "composition_technique": "string (in Traditional Chinese)",
          "patternType": "string (MUST be one of: 'rule_of_thirds', 's_curve', 'triangle', 'symmetry', 'none')",
          "ideal_x": float (0.0 to 1.0),
          "ideal_y": float (0.0 to 1.0),
          "actionable_tip": "string (in Traditional Chinese)",
          "ev_offset": float (-2.0 to 2.0),
          "flash_on": boolean,
          "scene_mode": "string (e.g., 夜景模式, 逆光人像, 晴天風景)"
        }
      ''');
      final imagePart = DataPart('image/png', pngBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 分析構圖中...')),
      );

      // 3. 呼叫 API
      final response = await _geminiModel.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      if (!mounted) return;
      
      String responseText = response.text?.trim() ?? '';
      
      try {
        // ⭐️ 防呆：清除 Gemini 可能回傳的 markdown json 標記
        responseText = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
        
        // 解析 JSON
        final data = jsonDecode(responseText);
        
        final technique = data['composition_technique'];
        final tip = data['actionable_tip'];
        final double newBestX = data['ideal_x'].toDouble();
        final double newBestY = data['ideal_y'].toDouble();
        
        // 抓取新的工具參數
        final String newPattern = data['patternType'] ?? 'none';
        final double evOffset = (data['ev_offset'] ?? 0.0).toDouble();
        final bool flashOn = data['flash_on'] ?? false;
        final String sceneMode = data['scene_mode'] ?? '一般模式';

        // 成功解析後，更新 UI 狀態
        setState(() {
          _bestX = newBestX; 
          _bestY = newBestY;
          _currentComposition = newPattern; // 觸發網格 UI 重新繪製
        });
        
        // 套用相機硬體設定
        await _cameraSettingsService.applyAISettings(
          controller: widget.cameraController,
          evOffset: evOffset,
          flashOn: flashOn,
          sceneMode: sceneMode,
          context: context,
        );

        // 顯示 AI 建議對話框
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('推薦構圖：$technique'),
              content: Text(tip),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('套用'),
                )
              ],
            ),
          );
        }

      } catch (e) {
        debugPrint('JSON Parsing Error: $e');
        debugPrint('Raw AI Response: $responseText');
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('AI 分析失敗，請再試一次')),
        );
      }

    } catch (e) {
      debugPrint('Gemini API Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('連線錯誤，請檢查網路狀態')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }
  Future<void> _processCameraImage(CameraImage image) async {
    _isProcessing = true;
    try {
      // 將影格交由 Service 處理，Service 回傳主體的相對座標 (0..1)
      final resultOffset = await _detectorService.detectMainSubject(
        image: image,
        camera: widget.cameraController!.description,
        deviceOrientation: MediaQuery.of(context).orientation,
      );

      // 若有偵測到主體，更新對應的座標值供 overlay 使用
      if (resultOffset != null) {
        setState(() {
          _subjectX = resultOffset.dx;
          _subjectY = resultOffset.dy;
        });
      }
    } catch (e) {
      debugPrint("Object Detection Error: $e");
    } finally {
      _isProcessing = false;
    }
  }
  // test single image
  Future<void> _runStaticImageTest() async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      final byteData = await rootBundle.load('test_images/food1.jpg');
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/food1_test.jpg');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      final decodedImage = await decodeImageFromList(await tempFile.readAsBytes());
      final imgWidth = decodedImage.width.toDouble();
      final imgHeight = decodedImage.height.toDouble();

      final resultOffset = await _detectorService.detectFromFilePath(
        filePath: tempFile.path,
        imgWidth: imgWidth,
        imgHeight: imgHeight,
      );

      setState(() {
        _testImageFile = tempFile; 
        if (resultOffset != null) {
          _subjectX = resultOffset.dx;
          _subjectY = resultOffset.dy;
          _hasGuidance = true;
          
          // 加入成功提示
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Object Detected! 成功抓到主體'), backgroundColor: Colors.green),
          );
        } else {
          _hasGuidance = false;
          
          // 加入失敗提示
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ML Kit 未偵測到明確主體'), backgroundColor: Colors.red),
          );
        }
      });
    } catch (e) {
      debugPrint("Static Image Test Error: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }// end test single image
  @override
  Widget build(BuildContext context) {  
    final screenSize = MediaQuery.of(context).size;
    final aiBestPos = Offset(screenSize.width * _bestX, screenSize.height * _bestY);
    final aiSubjectPos = Offset(screenSize.width * _subjectX, screenSize.height * _subjectY);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ⭐️ 將底圖、網格與 AI Overlay 用 RepaintBoundary 包裝
          RepaintBoundary(
            key: _previewKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_testImageFile != null)
                  Image.file(_testImageFile!, fit: BoxFit.cover)
                else if (widget.cameraController != null && widget.cameraController!.value.isInitialized)
                  CameraPreview(widget.cameraController!)
                else
                  const Center(child: Text('Camera Preview', style: TextStyle(color: Colors.white54))),
                
                CompositionOverlayManager(
                  isVisible: _hasGuidance,
                  patternType: _currentComposition,
                ),
                
                AIGuidanceOverlay(
                  isVisible: _hasGuidance,
                  subjectPosition: aiSubjectPos,
                  bestPosition: aiBestPos,
                ),
              ],
            ),
          ),

          // 3) 主要 UI：頂部列 + 底部控制列 (這些不需要被截圖送給 API)
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
      bottomNavigationBar: Theme(
        data: ThemeData(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF121212),
          selectedItemColor: const Color(0xFF0A58F5),
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          currentIndex: 1,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Camera'),
            BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Library'),
            BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Edit'),
          ],
        ),
      ),
    );
  }
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Row(
            children: [
              // ⭐️ 將原本在右下角的「物件偵測開關」移到頂部
              IconButton(
                icon: Icon(
                  Icons.center_focus_strong,
                  color: _hasGuidance && _testImageFile == null ? const Color(0xFF0A58F5) : Colors.white,
                ),
                onPressed: () {
                  if (_testImageFile != null) {
                    setState(() => _testImageFile = null);
                  }
                  _toggleLiveDetection();
                },
              ),
              // 原本的閃光燈與翻轉鏡頭按鈕
              IconButton(
                icon: const Icon(Icons.flash_off, color: Colors.white),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.cameraswitch, color: Colors.white),
                onPressed: () {},
              ),
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
          // 左下角：原本是相簿，我們把它改成測試按鈕
          IconButton(
            icon: const Icon(Icons.image_search, color: Colors.white), // 測試圖示
            onPressed: _runStaticImageTest, // 點擊載入 food1.jpg 測試
          ),
          
          // 中間快門按鈕保持不變
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
          
          // 右下角：原本的相機即時偵測開關
          IconButton(
            icon: _isProcessing 
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(color: Color(0xFF0A58F5), strokeWidth: 2.0),
                  )
                : const Icon(Icons.auto_awesome, color: Colors.white, size: 28), // AI 閃亮圖示
            onPressed: _captureAndAskGemini, // ⭐️ 綁定到這裡
          ),
        ],
      ),
    );
  }
}