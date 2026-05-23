import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// 記得 import 剛才建立的工具檔案
import '../tools/rule_of_thirds_grid.dart';
import '../tools/ai_guidance_overlay.dart';

class FullScreenCameraScreen extends StatefulWidget {
  final CameraController? cameraController;

  const FullScreenCameraScreen({super.key, this.cameraController});

  @override
  State<FullScreenCameraScreen> createState() => _FullScreenCameraScreenState();
}

class _FullScreenCameraScreenState extends State<FullScreenCameraScreen> {
  // 控制是否顯示 AI 提示的狀態變數
  bool _hasGuidance = false;

  @override
  Widget build(BuildContext context) {
    // 取得螢幕尺寸，用來模擬未來 AI 算出的絕對座標
    final screenSize = MediaQuery.of(context).size;
    
    // 模擬 AI 產生的座標 (未來這些變數會從 Provider/Bloc/State 動態取得)
    final mockBestPos = Offset(screenSize.width / 3, screenSize.height / 3);
    final mockSubjectPos = Offset(screenSize.width / 2, screenSize.height / 2 + 50);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 底層：相機即時預覽
          if (widget.cameraController != null && widget.cameraController!.value.isInitialized)
            CameraPreview(widget.cameraController!)
          else
            const Center(
              child: Text(
                'Camera Preview',
                style: TextStyle(color: Colors.white54),
              ),
            ),

          // 2. 中層工具：三分法網格 (根據 _hasGuidance 決定是否顯示)
          RuleOfThirdsGrid(isVisible: _hasGuidance),

          // 3. 中層工具：動態 AI 指引層 (根據 _hasGuidance 決定是否顯示)
          AIGuidanceOverlay(
            isVisible: _hasGuidance,
            subjectPosition: mockSubjectPos,
            bestPosition: mockBestPos,
          ),

          // 4. 頂層：UI 操作介面
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
      
      // 底部導覽列
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
          currentIndex: 1, // 預設停留在 Camera
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
          IconButton(
            icon: const Icon(Icons.photo_library, color: Colors.white),
            onPressed: () {},
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFF0A58F5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 8),
            ],
          ),
          IconButton(
            // 開發測試用：點擊設定按鈕來切換 _hasGuidance 的狀態
            icon: Icon(
              Icons.settings, 
              color: _hasGuidance ? const Color(0xFF0A58F5) : Colors.white, // 啟動時變色提示
            ),
            onPressed: () {
              setState(() {
                _hasGuidance = !_hasGuidance;
              });
            },
          ),
        ],
      ),
    );
  }
}