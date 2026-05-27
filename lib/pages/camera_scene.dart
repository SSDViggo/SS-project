import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 為了 rootBundle
import 'package:path_provider/path_provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// 工具模組：網格、AI 引導 overlay、以及物件偵測服務
import '../tools/rule_of_thirds_grid.dart';
import '../tools/ai_guidance_overlay.dart';
import '../tools/object_detector_service.dart';

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
  
  double _subjectX = 0.5;
  double _subjectY = 0.5;
  final double _bestX = 0.9;
  final double _bestY = 0.66;

  final ObjectDetectorService _detectorService = ObjectDetectorService();

  @override
  void initState() {
    super.initState();
    // 初始化物件偵測 Service。如果需要可在此傳入模型或設定
    _detectorService.initialize();
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
          // 1) 底層：測試圖片優先，否則顯示相機預覽
          if (_testImageFile != null)
            Image.file(_testImageFile!, fit: BoxFit.cover)
          else if (widget.cameraController != null && widget.cameraController!.value.isInitialized)
            CameraPreview(widget.cameraController!)
          else
            const Center(
              child: Text('Camera Preview', style: TextStyle(color: Colors.white54)),
            ),

          // 2) 構圖網格與 AI 引導 overlay（使用正規化座標）
          RuleOfThirdsGrid(isVisible: _hasGuidance),
          AIGuidanceOverlay(
            isVisible: _hasGuidance,
            subjectPosition: aiSubjectPos,
            bestPosition: aiBestPos,
          ),

          // 3) 主要 UI：頂部列 + 底部控制列
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
            icon: Icon(
              Icons.center_focus_strong,
              color: _hasGuidance && _testImageFile == null ? const Color(0xFF0A58F5) : Colors.white,
            ),
            onPressed: () {
              // 若處於測試圖片模式，先清除圖片退回相機畫面
              if (_testImageFile != null) {
                setState(() => _testImageFile = null);
              }
              _toggleLiveDetection();
            },
          ),
        ],
      ),
    );
  }
}