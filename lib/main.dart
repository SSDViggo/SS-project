import 'dart:io'; // 需要用來判斷 Platform
import 'package:camera/camera.dart'; // 導入 camera 套件
import 'package:flutter/material.dart';

import 'pages/camera_scene.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/composition_library_screen.dart';

// 1. 宣告全域變數來儲存設備上可用的相機列表
List<CameraDescription> cameras = [];

// 2. 將 main 函式改為 async
Future<void> main() async {
  // 確保 Flutter 引擎與底層綁定完成
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 修改路徑並加上 try-catch 防禦，避免沒讀到就讓整個 App 死機
  try {
    // 💡 注意：這裡的路徑必須跟你在 pubspec.yaml 裡寫的一模一樣
    await dotenv.load(fileName: "assets/.env");
    debugPrint('✅ .env 環境變數載入成功');
  } catch (e) {
    debugPrint('❌ .env 載入失敗: $e');
  }

  // 取得設備上所有可用的相機
  try {
    cameras = await availableCameras();
    debugPrint('📸 成功取得相機列表');
  } catch (e) {
    debugPrint('❌ 取得相機失敗: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Photo Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
        ),
      ),
      home: const PhotoAssistantScreen(),
    );
  }
}

// 3. 將原本的 StatelessWidget 改為 StatefulWidget 以管理 CameraController 的生命週期
class PhotoAssistantScreen extends StatefulWidget {
  const PhotoAssistantScreen({super.key});

  @override
  State<PhotoAssistantScreen> createState() => _PhotoAssistantScreenState();
}

class _PhotoAssistantScreenState extends State<PhotoAssistantScreen> {
  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    _initCamera(); // 進入首頁時就在背景預先初始化相機
  }

  // 4. 初始化 CameraController 的邏輯
  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;

    // 選擇 cameras[0] (通常是後置鏡頭)
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium, // 偵測用不需要太高畫質，避免過熱與延遲
      // 確保 Android 使用 nv21 格式以相容 Google ML Kit
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
    } catch (e) {
      debugPrint('相機初始化失敗: $e');
    }
  }

  @override
  void dispose() {
    // 退出 App 時釋放相機資源
    _cameraController?.dispose();
    super.dispose();
  }

  void _openCamera(BuildContext context) {
    // 5. 將初始化完成的 _cameraController 傳遞給相機頁面
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => FullScreenCameraScreen(
          cameraController: _cameraController, 
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Photo Assistant',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Your intelligent photography companion for perfect composition and professional editing',
              style: TextStyle(
                color: Color(0xFF8B9CB6),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  FeatureCard(
                    icon: Icons.camera_alt_outlined,
                    title: 'Smart Camera',
                    description: 'Real-time AI guidance with composition grids and level detection',
                    isPrimary: true,
                    onTap: () => _openCamera(context),
                  ),
                  const SizedBox(height: 16),
                  const FeatureCard(
                    icon: Icons.auto_awesome,
                    title: 'AI Enhancements',
                    description: 'Intelligent post-processing suggestions and manual controls',
                    isPrimary: false,
                  ),
                  const SizedBox(height: 16),
                  FeatureCard(
                    icon: Icons.grid_view_rounded,
                    title: 'Composition Library',
                    description: 'Learn composition techniques and visual guides',
                    isPrimary: false,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const CompositionLibraryScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF121212),
        selectedItemColor: const Color(0xFF0A58F5),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) {
            _openCamera(context);
          } else if (index == 2) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const CompositionLibraryScreen(),
              ),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_on),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: 'Edit',
          ),
        ],
      ),
    );
  }
}

/// 自訂的選項卡片 Widget (保持不變，為符合 const 規範加上 const)
class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isPrimary;
  final VoidCallback? onTap;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.isPrimary = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary ? const Color(0xFF105BFB) : const Color(0xFF1E1E22),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isPrimary ? null : Border.all(color: Colors.white12, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withOpacity(0.2)
                      : const Color(0xFF1A2A4A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isPrimary ? Colors.white : const Color(0xFF4A88FF),
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    color: isPrimary
                        ? Colors.white.withOpacity(0.9)
                        : const Color(0xFF9AA4B5),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}