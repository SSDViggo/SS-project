import 'dart:io';
import 'dart:ui' as ui; // 用於將RepaintBoundary畫面轉成PNG
import 'package:flutter/rendering.dart'; // 為了使用 RenderRepaintBoundary

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 為了 rootBundle
import 'package:path_provider/path_provider.dart';

// 工具模組：網格、AI 引導 overlay、物件偵測、相機設定、Gemini構圖建議
import '../tools/ai_guidance_overlay.dart';
import '../tools/object_detector_service.dart';
import '../tools/composition_overlay_manager.dart';
import '../tools/camera_settings_service.dart';
import '../tools/gemini_composition_service.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';
import '../screens/library_screen.dart';
import '../main.dart' show cameras;

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

  // 負責呼叫Gemini取得構圖建議，prompt/API呼叫/JSON解析都封裝在service內
  final GeminiCompositionService _geminiService = GeminiCompositionService();

  double _subjectX = 0.5;
  double _subjectY = 0.5;
  double _bestX = 0.9;
  double _bestY = 0.66;

  final ObjectDetectorService _detectorService = ObjectDetectorService();

  // 可變的相機控制器：由本畫面自行建立並管理生命週期
  CameraController? _controller;
  FlashMode _flashMode = FlashMode.off;
  bool _isCameraInitializing = true;
  bool _isFlipping = false; // 防止同一次翻轉動作被重複觸發

  @override
  void initState() {
    super.initState();
    // 初始化物件偵測 Service
    _detectorService.initialize();

    if (widget.cameraController != null) {
      // 呼叫端已經傳入初始化好的controller（向後相容）
      _controller = widget.cameraController;
      _isCameraInitializing = false;
    } else {
      // 由本畫面自己建立並初始化controller
      _initOwnCamera();
    }
  }

  /// 建立並初始化一個由本畫面自己管理的CameraController（預設後置鏡頭）
  Future<void> _initOwnCamera() async {
    if (cameras.isEmpty) {
      if (mounted) setState(() => _isCameraInitializing = false);
      return;
    }

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isCameraInitializing = false;
      });
    } catch (e) {
      debugPrint('相機初始化失敗: $e');
      if (mounted) setState(() => _isCameraInitializing = false);
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    // 本畫面自行建立的controller，離開時要自己釋放，避免資源洩漏與殭屍controller
    _controller?.dispose();
    _detectorService.dispose();
    super.dispose();
  }

  void _toggleLiveDetection() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    // 切換是否要顯示引導（同時啟/停相機影格串流）
    setState(() => _hasGuidance = !_hasGuidance);

    if (_hasGuidance) {
      // 啟動影格串流，回呼中只保留一個處理序列，避免重入
      await _controller!.startImageStream((CameraImage image) {
        if (_isProcessing) return;
        _processCameraImage(image);
      });
    } else {
      await _controller!.stopImageStream();
    }
  }

  /// 截取目前畫面、送給[GeminiCompositionService]分析，並套用回傳的構圖建議。
  Future<void> _captureAndAskGemini() async {
    if (_isProcessing) return;

    if (!_geminiService.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到Gemini API Key，請確認.env設定')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // 1. 透過RepaintBoundary取得當前畫面的截圖
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 分析構圖中...')),
      );

      // 2. 呼叫service分析構圖（prompt、API呼叫、JSON解析都在service內處理）
      final suggestion = await _geminiService.analyzeComposition(
        pngBytes,
        fallbackX: _bestX,
        fallbackY: _bestY,
      );

      if (!mounted) return;

      // 3. 套用建議：更新overlay座標與網格樣式
      setState(() {
        _bestX = suggestion.idealX;
        _bestY = suggestion.idealY;
        _currentComposition = suggestion.patternType;
      });

      // 4. 套用相機硬體設定（曝光、閃光燈）
      await _cameraSettingsService.applyAISettings(
        controller: _controller,
        evOffset: suggestion.evOffset,
        flashOn: suggestion.flashOn,
        sceneMode: suggestion.sceneMode,
        context: context,
      );

      // 5. 顯示AI建議對話框
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('推薦構圖：${suggestion.technique}'),
            content: Text(suggestion.tip),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('套用'),
              ),
            ],
          ),
        );
      }
    } on GeminiParseException catch (e) {
      debugPrint('JSON Parsing Error: ${e.message}');
      debugPrint('Raw AI Response: ${e.rawResponse}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 分析失敗，請再試一次')),
        );
      }
    } on GeminiRequestException catch (e) {
      debugPrint('Gemini API Error: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('連線錯誤，請檢查網路狀態')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted) return;
    _isProcessing = true;
    try {
      // 將影格交由 Service 處理，Service 回傳主體的相對座標 (0..1)
      final resultOffset = await _detectorService.detectMainSubject(
        image: image,
        camera: _controller!.description,
        deviceOrientation: MediaQuery.of(context).orientation,
      );

      // 若有偵測到主體，更新對應的座標值供 overlay 使用
      if (resultOffset != null && mounted) {
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
  // 靜態圖片測試（沒有實體相機/模擬器相機異常時，用內建圖片測試ML Kit偵測）
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
  }

  /// 拍照並存入裝置的應用程式文件目錄，然後加進CameraProvider的清單中
  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('相機尚未初始化')),
      );
      return;
    }
    if (_isProcessing) return;

    // 拍照前如果正在做即時偵測串流，需先暫停，避免衝突
    final wasStreaming = controller.value.isStreamingImages;
    if (wasStreaming) {
      await controller.stopImageStream();
    }

    setState(() => _isProcessing = true);

    try {
      final XFile rawFile = await controller.takePicture();

      // 將拍到的照片複製到App的文件目錄下，給一個唯一的檔名
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';
      await File(rawFile.path).copy(savedPath);

      if (!mounted) return;

      context.read<CameraProvider>().addPhoto(savedPath);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存到圖庫'), backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('拍照失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('拍照失敗，請再試一次'), backgroundColor: Colors.red),
        );
      }
    } finally {
      // 拍照完成後，如果原本有在做即時偵測，恢復串流
      if (wasStreaming && mounted) {
        await controller.startImageStream((CameraImage image) {
          if (_isProcessing) return;
          _processCameraImage(image);
        });
      }
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  /// 翻轉前後鏡頭：釋放目前的controller，建立新方向的controller並重新初始化
  Future<void> _flipCamera() async {
    if (cameras.length < 2 || _controller == null || _isProcessing || _isFlipping) return;
    // 立即同步上鎖，避免setState尚未生效前的重複點擊
    _isFlipping = true;

    final currentDirection = _controller!.description.lensDirection;
    final newCameraDescription = cameras.firstWhere(
      (c) => c.lensDirection != currentDirection,
      orElse: () => cameras.first,
    );

    setState(() => _isProcessing = true);

    final wasStreaming = _controller!.value.isStreamingImages;
    final oldController = _controller;

    try {
      if (wasStreaming) {
        await oldController!.stopImageStream();
      }

      final newController = CameraController(
        newCameraDescription,
        ResolutionPreset.medium,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await newController.initialize();
      await newController.setFlashMode(_flashMode);

      if (!mounted) {
        await newController.dispose();
        await oldController?.dispose();
        return;
      }

      // 先讓畫面切換到新的controller
      setState(() => _controller = newController);

      // 等這一輪畫面真正重繪完成後，才釋放舊的controller，
      // 避免舊的CameraPreview在重繪前因dispose的通知而存取已釋放的controller
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController?.dispose();
      });

      if (wasStreaming) {
        await newController.startImageStream((CameraImage image) {
          if (_isProcessing) return;
          _processCameraImage(image);
        });
      }
    } catch (e) {
      debugPrint('翻轉鏡頭失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('翻轉鏡頭失敗')),
        );
      }
    } finally {
      _isFlipping = false;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 切換閃光燈模式（關閉 / 持續開啟）
  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final newMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _controller!.setFlashMode(newMode);
      if (mounted) setState(() => _flashMode = newMode);
    } catch (e) {
      debugPrint('設定閃光燈失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('此裝置不支援閃光燈設定')),
        );
      }
    }
  }

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
          // 將底圖、網格與AI Overlay用RepaintBoundary包裝，供_captureAndAskGemini截圖使用
          RepaintBoundary(
            key: _previewKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_testImageFile != null)
                  Image.file(_testImageFile!, fit: BoxFit.cover)
                else if (_controller != null && _controller!.value.isInitialized)
                  CameraPreview(_controller!)
                else if (_isCameraInitializing)
                  const Center(child: CircularProgressIndicator(color: Color(0xFF0A58F5)))
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
          onTap: (index) {
            switch (index) {
              case 0: // Home
                Navigator.of(context).maybePop();
                break;
              case 1: // Camera（目前所在頁面，不做事）
                break;
              case 2: // Library
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LibraryScreen()),
                );
                break;
              case 3: // Edit（尚未實作）
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('編輯功能尚未完成')),
                );
                break;
            }
          },
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
              // 即時物件偵測開關
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
              // 閃光燈開關
              IconButton(
                icon: Icon(
                  _flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on,
                  color: _flashMode == FlashMode.off ? Colors.white : Colors.amber,
                ),
                onPressed: _toggleFlash,
              ),
              // 翻轉前後鏡頭
              IconButton(
                icon: const Icon(Icons.cameraswitch, color: Colors.white),
                onPressed: _flipCamera,
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
          
          // 中間快門按鈕：點擊拍照
          GestureDetector(
            onTap: _isProcessing ? null : _takePicture,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A58F5).withOpacity(_isProcessing ? 0.5 : 1.0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          
          // 右下角：原本的相機即時偵測開關
          IconButton(
            icon: _isProcessing 
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(color: Color(0xFF0A58F5), strokeWidth: 2.0),
                  )
                : const Icon(Icons.auto_awesome, color: Colors.white, size: 28), // AI 閃亮圖示
            onPressed: _captureAndAskGemini,
          ),
        ],
      ),
    );
  }
}