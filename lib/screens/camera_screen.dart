import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../repositories/photo_repo.dart';
import '../tools/ai_guidance_overlay.dart';
import '../tools/agent_thinking_log.dart';
import '../tools/composition_overlay_manager.dart';
import '../tools/gemini_composition_service.dart';
import '../tools/object_detector_service.dart'; // ⭐️ 引入你寫好的 Service
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
  CameraWorkflow _workflow = CameraWorkflow.live;
  String _subjectLabel = '分析中...';

  bool _isProcessing = false;
  bool _isThinking = false;
  String _currentComposition = 'none';
  final GlobalKey _previewKey = GlobalKey();

// ⭐️ 新增：ML Kit 狀態追蹤變數
  bool _isDetecting = false;
  DetectionResult? _latestDetection;
  int? _lockedTrackingId; // 儲存 Gemini 決定鎖定的 ID
  bool _showDebugBoxes = false;
  List<int> _currentIgnoredIds = [];

  Rect? _currentSubjectRect;
  Rect? _targetSubjectRect;
  List<String> _reasoningSteps = [];
  String _directionHint = '';
  List<GuideLine> _guideLines = [];
  
  // ⭐️ 解開 ML Kit Service 的封印
  final ObjectDetectorService _detectorService = ObjectDetectorService();
  final GeminiCompositionService _geminiService = GeminiCompositionService();

  CameraController? _controller;
  bool _isCameraInitializing = true;

  @override
  void initState() {
    super.initState();
    _detectorService.initialize(); // ⭐️ 初始化 ML Kit

    if (widget.cameraController != null) {
      _controller = widget.cameraController;
      _isCameraInitializing = false;
      _startImageStream(); // ⭐️ 啟動影像串流
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
        ResolutionPreset.high, // ⭐️ 關鍵修改：將 high 改為 medium
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
      
      _startImageStream(); // ⭐️ 相機準備好後，開始持續餵畫面給 ML Kit

    } catch (e) {
      debugPrint('相機初始化失敗: $e');
      if (mounted) setState(() => _isCameraInitializing = false);
    }
  }

  /// ⭐️ 啟動即時影像串流給 ML Kit 偵測
  void _startImageStream() {
    if (_controller?.value.isStreamingImages == false) {
      _controller?.startImageStream(_processCameraImage);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // ⭐️ 修正：移除 150ms 的時間判斷，讓畫面保持連貫，ML Kit 才能追蹤特徵點！
    // 只要依賴 _isDetecting 這個天然的鎖，就不會造成 GC 記憶體溢出。
    if (_isDetecting || _workflow == CameraWorkflow.analyzing) return;
    
    _isDetecting = true;

    try {
      // 交給 Service 進行辨識
      final result = await _detectorService.detectMainSubject(
        image: image,
        camera: _controller!.description,
        deviceOrientation: MediaQuery.of(context).orientation,
      );

      if (mounted && result != null) {
        setState(() {
          _latestDetection = result;

          // 動態追蹤：如果是在引導模式，持續更新黃框的位置！
          // 動態追蹤與自動覺醒機制
          if (_workflow == CameraWorkflow.guiding && _lockedTrackingId != null) {
            if (_lockedTrackingId == -1 && _currentSubjectRect != null) {
              // ⭐️ 自動覺醒機制 (Auto-Awake)
              // 處於 -1 幻影模式時，不斷掃描是否有新的框出現在幻影黃框附近
              NormalizedBox? bestMatchBox;
              double bestIoU = 0.0;
              double minDistance = 0.4; // 容忍半徑 (距離小於畫面寬高比例的 30%)

              for (var box in result.allBoxes) {
                // 絕對不能是黑名單裡的背景 (例如窗戶、地板)
                if (_currentIgnoredIds.contains(box.trackingId)) continue;

                final iou = _calculateIoU(box.rect, _currentSubjectRect);
                final boxCenter = box.rect.center;
                final phantomCenter = _currentSubjectRect!.center;
                final distance = (boxCenter - phantomCenter).distance;

                // 條件：只要有一點點重疊，或是中心點距離夠近，就認為這隻貓咪現身了！
                if (iou > 0.05 || distance < minDistance) {
                  if (iou > bestIoU) {
                    bestIoU = iou;
                    bestMatchBox = box;
                  } else if (bestIoU == 0.0 && distance < minDistance) {
                    minDistance = distance;
                    bestMatchBox = box;
                  }
                }
              }

              if (bestMatchBox != null) {
                // 💡 成功覺醒！將 -1 替換成真正的 ML Kit ID
                _lockedTrackingId = bestMatchBox.trackingId;
                _currentSubjectRect = bestMatchBox.rect;
                
                // 通知底層 Service 正式鎖定這個新 ID，並保持原本的黑名單防護
                _detectorService.lockTargetFromGemini(
                  _lockedTrackingId!, 
                  _subjectLabel,
                  ignoredIds: _currentIgnoredIds
                );
              }
            } else {
              // 正常動態追蹤模式 (已鎖定真實 ID)
              final lockedBox = result.allBoxes
                  .where((b) => b.trackingId == _lockedTrackingId)
                  .firstOrNull;
                  
              if (lockedBox != null) {
                _currentSubjectRect = lockedBox.rect; // ML Kit 即時更新的最新座標
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Object detection error: $e');
    } finally {
      _isDetecting = false;
    }
  }
  

  double _calculateIoU(Rect? rect1, Rect? rect2) {
    if (rect1 == null || rect2 == null) return 0.0;

    final intersection = rect1.intersect(rect2);
    if (intersection.width < 0 || intersection.height < 0) {
      return 0.0; // 沒有交集
    }

    final intersectionArea = intersection.width * intersection.height;
    final unionArea = (rect1.width * rect1.height) + (rect2.width * rect2.height) - intersectionArea;

    return intersectionArea / unionArea;
  }

  void dispose() {
    if (_controller?.value.isStreamingImages == true) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();
    _detectorService.dispose(); // ⭐️ 釋放 ML Kit
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

    try {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('無法取得預覽畫面，請稍後再試');

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('無法轉換預覽畫面資料');
      
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      setState(() {
        _frozenFrameBytes = pngBytes;
      });

      // ⭐️ 關鍵修改：將最新的 ML Kit 框框資訊連同截圖一併丟給 Gemini！
      // 註：這需要你去 GeminiCompositionService 的 analyzeComposition 方法加上 boxes 參數
      final latestBoxes = _latestDetection?.allBoxes ?? [];
      final suggestion = await _geminiService.analyzeComposition(pngBytes, latestBoxes);

      if (!mounted) return;

      setState(() {
        _reasoningSteps = suggestion.reasoningSteps;
        _guideLines = suggestion.actionPlan.uiGuides.guideLines;
        _currentComposition = suggestion.actionPlan.selectedTool;

        // ⭐️ 解析目標位置 (藍框) 與距離提示
        if (suggestion.actionPlan.movements.isNotEmpty) {
          final movement = suggestion.actionPlan.movements.first;
          _directionHint = movement.directionHint;
          _targetSubjectRect = Rect.fromLTRB(
              movement.targetBoundingBox[0], movement.targetBoundingBox[1],
              movement.targetBoundingBox[2], movement.targetBoundingBox[3]);
              
          // ⭐️ 提取 Gemini 選出的終極目標 ID
          _lockedTrackingId = movement.trackingId; 
        }

        // ⭐️ 核心防呆邏輯：處理 tracking_id == -1 的情況
        if (suggestion.perception.detectedSubjects.isNotEmpty) {
          _currentIgnoredIds = suggestion.actionPlan.ignoredTrackingIds; // ⭐️ 儲存黑名單

          if (_lockedTrackingId != null && _lockedTrackingId != -1) {
            // 狀況 A：AI 覺得框框大小合適，決定正式鎖定
            final subject = suggestion.perception.detectedSubjects.firstWhere(
              (s) => s.trackingId == _lockedTrackingId,
              orElse: () => suggestion.perception.detectedSubjects.first
            );
            
            _subjectLabel = subject.label;
            _currentSubjectRect = Rect.fromLTRB(
                subject.boundingBox[0], subject.boundingBox[1],
                subject.boundingBox[2], subject.boundingBox[3]);
                
            _detectorService.lockTargetFromGemini(
               _lockedTrackingId!, 
               _subjectLabel,
               ignoredIds: _currentIgnoredIds // 傳遞黑名單給 ML Kit！
            );
          } else {
            // 🚨 狀況 B：AI 覺得貓咪太小沒有專屬框，回傳了 -1
            final subject = suggestion.perception.detectedSubjects.first;
            _subjectLabel = subject.label;
            
            _currentSubjectRect = Rect.fromLTRB(
                subject.boundingBox[0], subject.boundingBox[1],
                subject.boundingBox[2], subject.boundingBox[3]);
                
            _detectorService.resetLock(); 
            
            // 鎖定為 -1，套用黑名單防護
            _detectorService.lockTargetFromGemini(-1, _subjectLabel, ignoredIds: _currentIgnoredIds);
          }
        }
        _isThinking = true;
      });

    } on GeminiParseException catch (e) {
      debugPrint('JSON Parsing Error: ${e.message}');
      debugPrint('Raw AI Response: ${e.rawResponse}');
      _resetToLive(errorMsg: 'AI 分析失敗，請再試一次');
    } catch (e) {
      debugPrint('Gemini Error: $e');
      _resetToLive(errorMsg: '連線或處理錯誤，請再試一次');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _resetToLive({String? errorMsg}) {
    if (mounted) {
      setState(() {
        _workflow = CameraWorkflow.live;
        _frozenFrameBytes = null;
        _detectorService.resetLock(); // ⭐️ 發生錯誤或重置時解除 ML Kit 鎖定
      });
      if (errorMsg != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    }
  }

  // ... _takePicture 與 _showReasoningLogDialog 保持原本的實作不變 ...
  /// ⭐️ 實際的拍照邏輯
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

    debugPrint('takePicture: start');
    setState(() => _isProcessing = true);

    try {
      // 拍下照片
      final XFile rawFile = await controller.takePicture();
      debugPrint('takePicture: captured rawFile=${rawFile.path}');

      // 複製到 App 內部資料夾
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';
      await File(rawFile.path).copy(savedPath);
      debugPrint('takePicture: saved local copy at $savedPath');

      if (!mounted) return;
      context.read<CameraProvider>().addPhoto(savedPath);

      final photoRepo = PhotoRepository();
      debugPrint('takePicture: uploading file to Firebase');
      final uploadedUrl = await photoRepo.uploadPhoto(File(savedPath));
      debugPrint('takePicture: Firebase upload successful: $uploadedUrl');

      // 3. 使用 gal 將照片存入手機的公開相簿 (Gallery)
      await Gal.putImage(savedPath);
      debugPrint('takePicture: saved to gallery');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已儲存到圖庫，Firebase URL: $uploadedUrl'), backgroundColor: Colors.green),
        );
      }
    } catch (e, st) {
      debugPrint('takePicture failed: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照或上傳失敗：$e'), backgroundColor: Colors.red),
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
    final isAligned = _calculateIoU(_currentSubjectRect, _targetSubjectRect) > 0.85;

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

                // 假凍結畫面層
                if (_frozenFrameBytes != null)
                  Positioned.fill(
                    child: Image.memory(
                      _frozenFrameBytes!,
                      fit: BoxFit.cover,
                    ),
                  ),

                // ⭐️ 可選：如果在 live 模式你想顯示 ML Kit 即時抓到的所有未命名白框，可以加在這裡
                // ⭐️ 修正顯示條件：讓 live 和 guiding 模式都能看到紅框，方便 Debug
                if (_showDebugBoxes && 
                    (_workflow == CameraWorkflow.live || _workflow == CameraWorkflow.guiding) && 
                    _latestDetection != null)
                  ..._latestDetection!.allBoxes.map((box) {
                    return Positioned(
                      left: box.rect.left * screenSize.width,
                      top: box.rect.top * screenSize.height,
                      width: box.rect.width * screenSize.width,
                      height: box.rect.height * screenSize.height,
                      child: Container(
                        decoration: BoxDecoration(
                          // 如果這個框剛好是被 AI 鎖定的 ID，可以用不同顏色標示 (可選)
                          border: Border.all(
                            color: box.trackingId == _lockedTrackingId ? Colors.green : Colors.redAccent, 
                            width: box.trackingId == _lockedTrackingId ? 3.0 : 2.0
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            color: box.trackingId == _lockedTrackingId ? Colors.green : Colors.redAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              'ID: ${box.trackingId}',
                              style: const TextStyle(
                                color: Colors.white, 
                                fontSize: 12, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                
                if (_workflow == CameraWorkflow.analyzing)
                  Container(
                    color: Colors.black.withOpacity(0.6),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Color(0xFF0A58F5)),
                          const SizedBox(height: 16),
                          Text(
                            !_isThinking ? '正在傳送照片給AI攝影助理...' : 'AI攝影助理正在分析畫面...',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          if (_isThinking) ...[
                            const SizedBox(height: 32),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: AgentThinkingLog(
                                steps: _reasoningSteps,
                                onComplete: () {
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

                CompositionOverlayManager(
                  isVisible: showGuidance,
                  patternType: _currentComposition,
                ),
                AIGuidanceOverlay(
                  isVisible: showGuidance,
                  // ⭐️ 只要進入 guiding，黃框就會吃 ML Kit 的動態座標
                  currentRect: showGuidance ? yellowRect : null,
                  targetRect: blueRect,
                  subjectLabel: _subjectLabel,
                  isAligned: isAligned,
                ),
                
                if (showGuidance)
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

          if (showGuidance)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF0A58F5), width: 1.5)),
                child: Text(
                  _workflow == CameraWorkflow.magicMoment
                      ? '💡 AI 指示：$_directionHint'
                      : '請移動手機，將 [$_subjectLabel] 放入藍色光圈中。',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          if (_workflow == CameraWorkflow.magicMoment)
            Positioned(
              bottom: 150,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _frozenFrameBytes = null; 
                      _workflow = CameraWorkflow.guiding;
                    });
                  },
                  icon: const Icon(Icons.compare_arrows, color: Colors.white),
                  label: const Text('開始移動',
                      style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A58F5),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左側按鈕群：關閉按鈕 + Debug 按鈕
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(width: 12), // 加上間距
              // ⭐️ 移到左側：切換顯示偵測紅框的按鈕
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _showDebugBoxes ? Icons.visibility : Icons.visibility_off,
                    color: _showDebugBoxes ? Colors.redAccent : Colors.white,
                  ),
                  tooltip: '切換 ML Kit 偵測框',
                  onPressed: () {
                    setState(() {
                      _showDebugBoxes = !_showDebugBoxes;
                    });
                  },
                ),
              ),
            ],
          ),
          
          // 右側：保持為空，留給下方 Stack 裡的 AI 思考按鈕 (Positioned: right: 20, top: 40)
          const SizedBox.shrink(),
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
              // ⭐️ 清除鎖定並回到 Live 狀態
              _detectorService.resetLock();
              setState(() {
                _workflow = CameraWorkflow.live;
                _currentComposition = 'none';
                _frozenFrameBytes = null;
                
                // ⭐️ 確保把所有狀態徹底清空，才不會影響下一次辨識
                _lockedTrackingId = null; 
                _currentSubjectRect = null; 
                _targetSubjectRect = null; 
                _currentIgnoredIds = []; 
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
                  child: const Icon(Icons.camera, color: Colors.white, size: 34),
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