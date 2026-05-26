import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:io';
import 'package:flutter/services.dart'; // 為了 rootBundle
import 'package:path_provider/path_provider.dart';

// 匯入工具檔案
import '../tools/rule_of_thirds_grid.dart';
import '../tools/ai_guidance_overlay.dart';
import '../tools/object_detector_service.dart';

class FullScreenCameraScreen extends StatefulWidget {
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
  final double _bestX = 0.66;
  final double _bestY = 0.66;

  final ObjectDetectorService _detectorService = ObjectDetectorService();

  @override
  void initState() {
    super.initState();
    // 初始化 Detector
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

    setState(() {
      _hasGuidance = !_hasGuidance;
    });

    if (_hasGuidance) {
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
      // 直接呼叫 Service，把複雜的邏輯封裝在底層
      final resultOffset = await _detectorService.detectMainSubject(
        image: image,
        camera: widget.cameraController!.description,
        deviceOrientation: MediaQuery.of(context).orientation,
      );

      // 如果有抓到 Subject 的 Bounding Box，就更新 UI 狀態
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
      // 1. 從 Asset 讀取圖片，並寫入手機暫存區 (為了取得真實路徑)
      final byteData = await rootBundle.load('test_images/food1.jpg');
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/food1_test.jpg');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      // 2. 取得圖片的真實寬高 (為了解析相對座標)
      final decodedImage = await decodeImageFromList(await tempFile.readAsBytes());
      final imgWidth = decodedImage.width.toDouble();
      final imgHeight = decodedImage.height.toDouble();

      // 3. 呼叫 Service 分析這張靜態圖片
      final resultOffset = await _detectorService.detectFromFilePath(
        filePath: tempFile.path,
        imgWidth: imgWidth,
        imgHeight: imgHeight,
      );

      // 4. 更新 UI，將畫面從相機切換成測試圖片，並標示出座標
      setState(() {
        _testImageFile = tempFile; // 設定這張圖後，畫面會切換
        if (resultOffset != null) {
          _subjectX = resultOffset.dx;
          _subjectY = resultOffset.dy;
          _hasGuidance = true;
        } else {
          // 如果沒辨識到主體，關閉引導
          _hasGuidance = false;
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
  // end test single image
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
          // 1. 底層：若有測試圖片就顯示圖片，否則顯示相機
          if (_testImageFile != null)
            Image.file(_testImageFile!, fit: BoxFit.cover)
          else if (widget.cameraController != null && widget.cameraController!.value.isInitialized)
            CameraPreview(widget.cameraController!)
          else
            const Center(child: Text('Camera Preview', style: TextStyle(color: Colors.white54))),

          // 2. 網格與 AI 標籤 (這部分不用動，因為它吃的是正規化座標)
          RuleOfThirdsGrid(isVisible: _hasGuidance),
          AIGuidanceOverlay(
            isVisible: _hasGuidance,
            subjectPosition: aiSubjectPos,
            bestPosition: aiBestPos,
          ),

          // 3. UI 介面
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