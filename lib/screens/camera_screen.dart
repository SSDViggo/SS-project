import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../tools/ai_guidance_overlay.dart';
import '../tools/agent_thinking_log.dart';
import '../tools/composition_overlay_manager.dart';
import '../tools/camera_settings_service.dart';
import '../tools/gemini_composition_service.dart';
import '../providers/camera_provider.dart';
import '../main.dart' show cameras;
import 'package:gal/gal.dart';

enum CameraWorkflow { live, analyzing, magicMoment, guiding }

class FullScreenCameraScreen extends StatefulWidget {
  final CameraController? cameraController;

  const FullScreenCameraScreen({super.key, this.cameraController});

  @override
  State<FullScreenCameraScreen> createState() => _FullScreenCameraScreenState();
}

class _FullScreenCameraScreenState extends State<FullScreenCameraScreen> {
  Uint8List? _frozenFrameBytes;
  File? _testImageFile;
  CameraWorkflow _workflow = CameraWorkflow.live;
  String _subjectLabel = '分析中...';

  bool _isProcessing = false;
  bool _isThinking = false;
  String _currentComposition = 'none';
  final CameraSettingsService _cameraSettingsService = CameraSettingsService();
  final GlobalKey _previewKey = GlobalKey();

  Rect? _currentSubjectRect;
  Rect? _targetSubjectRect;
  List<String> _reasoningSteps = [];
  String _directionHint = '';
  List<GuideLine> _guideLines = [];

  List<Rect> _allDebugRects = [];
  // final ObjectDetectorService _detectorService = ObjectDetectorService();
  final GeminiCompositionService _geminiService = GeminiCompositionService();

  CameraController? _controller;
  bool _isCameraInitializing = true;

  @override
  void initState() {
    super.initState();
    // _detectorService.initialize();

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
    // _detectorService.dispose();
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

    setState(() {
      _isProcessing = true;
      _workflow = CameraWorkflow.analyzing;
      _isThinking = false;
      _reasoningSteps = [];
      _guideLines = [];
    });

    // if (wasStreaming) {
    //   await _stopTrackingStream();
    // }
    // await _controller?.pausePreview();

    try {
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('無法取得預覽畫面，請稍後再試');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('無法轉換預覽畫面資料');
      }
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      setState(() {
        _frozenFrameBytes = pngBytes;
      });

      final suggestion = await _geminiService.analyzeComposition(pngBytes);

      if (!mounted) return;

      setState(() {
        _reasoningSteps = suggestion.reasoningSteps;
        _guideLines = suggestion.actionPlan.uiGuides.guideLines;

        // 解析現在位置(黃框)與主體名稱
        if (suggestion.perception.detectedSubjects.isNotEmpty) {
          final subject = suggestion.perception.detectedSubjects.first;
          _subjectLabel = subject.name;

          _currentSubjectRect = Rect.fromLTRB(
              subject.boundingBox[0],
              subject.boundingBox[1],
              subject.boundingBox[2],
              subject.boundingBox[3]);
        }

        // 解析目標位置(藍框)與距離提示
        if (suggestion.actionPlan.movements.isNotEmpty) {
          final movement = suggestion.actionPlan.movements.first;
          _directionHint = movement.directionHint;

          _targetSubjectRect = Rect.fromLTRB(
              movement.targetBoundingBox[0],
              movement.targetBoundingBox[1],
              movement.targetBoundingBox[2],
              movement.targetBoundingBox[3]);
        }

        _currentComposition = suggestion.actionPlan.selectedTool;
        _isThinking = true;
      });

      // ⭐️ 關鍵新增：把大腦 (Gemini) 認出來的標籤，告訴眼睛 (ML Kit)
      _detectorService.updateTargetLabel(suggestion.detectedSubject);

      await _cameraSettingsService.applyAISettings(
        controller: _controller,
        evOffset: 0.0,
        flashOn: false,
        sceneMode: 'auto',
        context: context,
      );
    } on GeminiParseException catch (e) {
      debugPrint('JSON Parsing Error: ${e.message}');
      debugPrint('Raw AI Response: ${e.rawResponse}');
      await _controller?.resumePreview();
      if (mounted) {
        setState(() {
          _workflow = CameraWorkflow.live;
          _frozenFrameBytes = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('AI 分析失敗，請再試一次')));
      }
    } on GeminiRequestException catch (e) {
      debugPrint('Gemini API Error: ${e.message}');
      await _controller?.resumePreview();
      if (mounted) {
        setState(() {
          _workflow = CameraWorkflow.live;
          _frozenFrameBytes = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('連線錯誤，請檢查網路狀態')));
      }
    } on StateError catch (e) {
      debugPrint('Gemini capture error: $e');
      await _controller?.resumePreview();
      if (mounted) {
        setState(() {
          _workflow = CameraWorkflow.live;
          _frozenFrameBytes = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('無法取得畫面，請再試一次')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

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
      // 拍下照片
      final XFile rawFile = await controller.takePicture();

      // 複製到 App 內部資料夾
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';
      await File(rawFile.path).copy(savedPath);

      if (!mounted) return;
      context.read<CameraProvider>().addPhoto(savedPath);

      // 使用 gal 將照片存入手機的公開相簿
      await Gal.putImage(savedPath);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存到圖庫'), backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('拍照失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('拍照失敗，請再試一次'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showReasoningLogDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF0A58F5), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.psychology, color: Colors.white),
              SizedBox(width: 8),
              Text('Agent 思考過程',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _reasoningSteps
                  .map((step) => Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(
                          step,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, height: 1.5),
                        ),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // 關閉視窗
              child: const Text('了解',
                  style: TextStyle(
                      color: Color(0xFF0A58F5),
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final Rect? yellowRect = _currentSubjectRect != null
        ? Rect.fromLTRB(
            _currentSubjectRect!.left * screenSize.width,
            _currentSubjectRect!.top * screenSize.height,
            _currentSubjectRect!.right * screenSize.width,
            _currentSubjectRect!.bottom * screenSize.height,
          )
        : null;

    final Rect? blueRect = _targetSubjectRect != null
        ? Rect.fromLTRB(
            _targetSubjectRect!.left * screenSize.width,
            _targetSubjectRect!.top * screenSize.height,
            _targetSubjectRect!.right * screenSize.width,
            _targetSubjectRect!.bottom * screenSize.height,
          )
        : null;
    final showGuidance = _workflow == CameraWorkflow.magicMoment ||
        _workflow == CameraWorkflow.guiding;

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
                  const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF0A58F5)))
                else
                  const Center(
                      child: Text('Camera Preview',
                          style: TextStyle(color: Colors.white54))),

                // 假凍結畫面層
                if (_frozenFrameBytes != null)
                  Positioned.fill(
                    child: Image.memory(
                      _frozenFrameBytes!,
                      fit: BoxFit.cover, // 確保圖片填滿預覽區域不變形
                    ),
                  ),

                if (_workflow == CameraWorkflow.analyzing)
                  Container(
                    color: Colors.black.withOpacity(0.6),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // loading圈圈
                          const CircularProgressIndicator(
                              color: Color(0xFF0A58F5)),
                          const SizedBox(height: 16),
                          Text(
                            !_isThinking
                                ? '正在傳送照片給AI攝影助理...'
                                : 'AI攝影助理正在分析畫面...', // 進入打字機時，文字稍微改變更符合情境
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),

                          // 在 Loading 下方顯示打字機動畫
                          if (_isThinking) ...[
                            const SizedBox(height: 32),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: AgentThinkingLog(
                                steps: _reasoningSteps,
                                onComplete: () {
                                  // 轉到黃藍框畫面
                                  setState(() {
                                    _isThinking = false;
                                    _workflow = CameraWorkflow.magicMoment;
                                  });
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                AIGuidanceOverlay(
                  isVisible: showGuidance,
                  currentRect: _workflow == CameraWorkflow.magicMoment
                      ? yellowRect
                      : null,
                  targetRect: blueRect,
                  subjectLabel: _subjectLabel,
                  guideLines: _workflow == CameraWorkflow.magicMoment
                      ? _guideLines
                      : [],
                ),

                CompositionOverlayManager(
                  isVisible: showGuidance,
                  patternType: _currentComposition,
                ),
                AIGuidanceOverlay(
                  isVisible: showGuidance,
                  currentRect: _workflow == CameraWorkflow.magicMoment
                      ? yellowRect
                      : null,
                  targetRect: blueRect,
                  subjectLabel: _subjectLabel,
                ),
                
                // 查看思考按鈕
                if (_workflow == CameraWorkflow.magicMoment ||
                    _workflow == CameraWorkflow.guiding)
                  Positioned(
                    right: 20,
                    top: 40,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(
                        side: BorderSide(color: Color(0xFF0A58F5), width: 1.5),
                      ),
                      elevation: 4,
                      child: IconButton(
                        icon: const Icon(Icons.psychology, color: Colors.white),
                        tooltip: '查看 AI 思考過程',
                        onPressed: () {
                          if (_reasoningSteps.isNotEmpty) {
                            _showReasoningLogDialog();
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (_workflow == CameraWorkflow.magicMoment ||
              _workflow == CameraWorkflow.guiding)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: const Color(0xFF0A58F5), width: 1.5)),
                child: Text(
                  _workflow == CameraWorkflow.magicMoment
                      ? '💡 AI 指示：$_directionHint'
                      : '請移動手機，將 [$_subjectLabel] 放入藍色光圈中。',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // 開始移動按鈕
          if (_workflow == CameraWorkflow.magicMoment)
            Positioned(
              bottom: 150,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _frozenFrameBytes = null; // 清空假照片，底層即時相機就會透出來
                      _workflow = CameraWorkflow.guiding;
                    });
                  },
                  icon: const Icon(Icons.compare_arrows, color: Colors.white),
                  label: const Text('開始移動',
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A58F5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 8,
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
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A58F5)
                        .withOpacity(_isProcessing ? 0.5 : 1.0),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.camera, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          IconButton(
            icon: _workflow == CameraWorkflow.analyzing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Color(0xFF0A58F5), strokeWidth: 2.0),
                  )
                : const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
            onPressed: _captureAndAskGemini,
          ),
        ],
      ),
    );
  }
}