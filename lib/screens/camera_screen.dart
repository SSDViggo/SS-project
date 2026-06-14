import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../tools/ai_guidance_overlay.dart';
import '../tools/object_detector_service.dart';
import '../tools/composition_overlay_manager.dart';
import '../tools/camera_settings_service.dart';
import '../tools/gemini_composition_service.dart';
import '../providers/camera_provider.dart';
import '../main.dart' show cameras;
import 'package:gal/gal.dart';
enum CameraWorkflow {
  live,
  analyzing,
  magicMoment,
  guiding
}

class FullScreenCameraScreen extends StatefulWidget {
  final CameraController? cameraController;

  const FullScreenCameraScreen({super.key, this.cameraController});

  @override
  State<FullScreenCameraScreen> createState() => _FullScreenCameraScreenState();
}

class _FullScreenCameraScreenState extends State<FullScreenCameraScreen> {
  File? _testImageFile;
  CameraWorkflow _workflow = CameraWorkflow.live;
  String _subjectLabel = '分析中...';

  bool _isProcessing = false; 
  String _currentComposition = 'none'; 
  final CameraSettingsService _cameraSettingsService = CameraSettingsService();
  final GlobalKey _previewKey = GlobalKey();

  double _subjectX = 0.5;
  double _subjectY = 0.5;
  double _bestX = 0.9;
  double _bestY = 0.66;

  List<Rect> _allDebugRects = [];
  final ObjectDetectorService _detectorService = ObjectDetectorService();
  final GeminiCompositionService _geminiService = GeminiCompositionService();

  CameraController? _controller;
  bool _isCameraInitializing = true;

  Future<void> _startTrackingStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;

    await controller.startImageStream((image) {
      if (!_isProcessing) {
        _processCameraImage(image);
      }
    });
  }

  Future<void> _stopTrackingStream() async {
    final controller = _controller;
    if (controller?.value.isStreamingImages == true) {
      await controller!.stopImageStream();
    }
  }

  @override
  void initState() {
    super.initState();
    _detectorService.initialize();

    if (widget.cameraController != null) {
      _controller = widget.cameraController;
      _isCameraInitializing = false;
    } else {
      _initOwnCamera();
    }
  }

  Future<void> _initOwnCamera() async {
    if (cameras.isEmpty) {
      if (mounted) setState(() => _isCameraInitializing = false);
      return;
    }

    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final available = await availableCameras();
      if (!mounted || available.isEmpty) return;

      final backCamera = available.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => available.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

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
    if (_controller?.value.isStreamingImages == true) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();
    _detectorService.dispose();
    super.dispose();
  }
  
  Future<void> _captureAndAskGemini() async {
    if (_isProcessing || _workflow != CameraWorkflow.live) return;

    if (!_geminiService.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到Gemini API Key，請確認.env設定')),
      );
      return;
    }

    final wasStreaming = _controller?.value.isStreamingImages == true;
    setState(() {
      _isProcessing = true;
      _workflow = CameraWorkflow.analyzing;
    });

    if (wasStreaming) {
      await _stopTrackingStream();
    }
    await _controller?.pausePreview();

    try {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('無法取得預覽畫面，請稍後再試');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('無法轉換預覽畫面資料');
      }
      final Uint8List pngBytes = byteData.buffer.asUint8List();

     final suggestion = await _geminiService.analyzeComposition(
        pngBytes,
        fallbackX: _bestX,
        fallbackY: _bestY,
      );

      if (!mounted) return;

      setState(() {
        _bestX = suggestion.idealX;
        _bestY = suggestion.idealY;
        _currentComposition = suggestion.patternType;
        _subjectLabel = suggestion.detectedSubject;
        _workflow = CameraWorkflow.magicMoment;
      });

      // ⭐️ 關鍵新增：把大腦 (Gemini) 認出來的標籤，告訴眼睛 (ML Kit)
      _detectorService.updateTargetLabel(suggestion.detectedSubject);

      await _cameraSettingsService.applyAISettings(
        controller: _controller,
        evOffset: suggestion.evOffset,
        flashOn: suggestion.flashOn,
        sceneMode: suggestion.sceneMode,
        context: context,
      );

      await Future.delayed(const Duration(milliseconds: 2500));

      if (!mounted) return;

      await _controller?.resumePreview();

      setState(() {
        _workflow = CameraWorkflow.guiding;
      });

      if (_controller != null && _controller!.value.isStreamingImages == false) {
        await _startTrackingStream();
      }
    } on GeminiParseException catch (e) {
      debugPrint('JSON Parsing Error: ${e.message}');
      debugPrint('Raw AI Response: ${e.rawResponse}');
      await _controller?.resumePreview();
      if (mounted) {
        setState(() => _workflow = CameraWorkflow.live);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 分析失敗，請再試一次')));
      }
    } on GeminiRequestException catch (e) {
      debugPrint('Gemini API Error: ${e.message}');
      await _controller?.resumePreview();
      if (mounted) {
        setState(() => _workflow = CameraWorkflow.live);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('連線錯誤，請檢查網路狀態')));
      }
    } on StateError catch (e) {
      debugPrint('Gemini capture error: $e');
      await _controller?.resumePreview();
      if (mounted) {
        setState(() => _workflow = CameraWorkflow.live);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法取得畫面，請再試一次')));
      }
    } finally {
      if (wasStreaming && _controller?.value.isStreamingImages != true && mounted) {
        await _startTrackingStream();
      }
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted) return;
    _isProcessing = true;
    try {
      final result = await _detectorService.detectMainSubject(
        image: image,
        camera: _controller!.description,
        deviceOrientation: MediaQuery.of(context).orientation,
      );

      if (result != null && mounted) {
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

  void _runStaticImageTest() {}

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('相機尚未初始化')),
      );
      return;
    }
    if (_isProcessing) return;

    final wasStreaming = controller.value.isStreamingImages;
    if (wasStreaming) {
      await controller.stopImageStream();
    }

    setState(() => _isProcessing = true);

    try {
      // 1. 拍下照片
      final XFile rawFile = await controller.takePicture();

      // 2. 複製到 App 內部資料夾 (保留你原本供 Provider 使用的邏輯)
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';
      await File(rawFile.path).copy(savedPath);

      if (!mounted) return;
      context.read<CameraProvider>().addPhoto(savedPath);

      // 3. 使用 gal 將照片存入手機的公開相簿 (Gallery)
      await Gal.putImage(savedPath);

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
      if (wasStreaming && mounted) {
        await controller.startImageStream((image) {
          if (!_isProcessing) _processCameraImage(image);
        });
      }
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  
 @override
  Widget build(BuildContext context) {  
    final screenSize = MediaQuery.of(context).size;
    final aiBestPos = Offset(screenSize.width * _bestX, screenSize.height * _bestY);
    final aiSubjectPos = Offset(screenSize.width * _subjectX, screenSize.height * _subjectY);

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
                if (_controller != null && _controller!.value.isInitialized)
                  CameraPreview(_controller!)
                else if (_isCameraInitializing)
                  const Center(child: CircularProgressIndicator(color: Color(0xFF0A58F5)))
                else
                  const Center(child: Text('Camera Preview', style: TextStyle(color: Colors.white54))),
                
                CompositionOverlayManager(
                  isVisible: showGuidance,
                  patternType: _currentComposition,
                ),
                
                AIGuidanceOverlay(
                  isVisible: showGuidance,
                  subjectPosition: aiSubjectPos,
                  bestPosition: aiBestPos,
                  subjectLabel: _subjectLabel,
                  debugRects: _allDebugRects,
                  showSubjectAndArrow: true, 
                ),

                // 這裡修復了原本錯亂的括號
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
    );
  }
 Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Row(
            children: [],
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
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              if (_controller?.value.isStreamingImages == true) {
                _controller?.stopImageStream();
              }
              _detectorService.resetLock();
              setState(() {
                _workflow = CameraWorkflow.live;
                _currentComposition = 'none';
                _allDebugRects = [];
              });
            },
          ),
          
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