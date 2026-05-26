import 'package:flutter/material.dart';

import 'pages/camera_scene.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Photo Assistant',
      debugShowCheckedModeBanner: false,
      // 設定全域為深色主題
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

class PhotoAssistantScreen extends StatelessWidget {
  const PhotoAssistantScreen({super.key});

  void _openCamera(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const FullScreenCameraScreen(),
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
            // 頂部說明文字
            const Text(
              'Your intelligent photography companion for perfect composition and professional editing',
              style: TextStyle(
                color: Color(0xFF8B9CB6), // 偏藍灰色的字體
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            // 卡片列表區域
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  FeatureCard(
                    icon: Icons.camera_alt_outlined,
                    title: 'Smart Camera',
                    description: 'Real-time AI guidance with composition grids and level detection',
                    isPrimary: true, // 藍色主視角卡片
                    onTap: () => _openCamera(context),
                  ),
                  const SizedBox(height: 16),
                  FeatureCard(
                    icon: Icons.auto_awesome,
                    title: 'AI Enhancements',
                    description: 'Intelligent post-processing suggestions and manual controls',
                    isPrimary: false, // 深色背景卡片
                  ),
                  const SizedBox(height: 16),
                  FeatureCard(
                    icon: Icons.grid_view_rounded,
                    title: 'Composition Library',
                    description: '', // 畫面底部被截斷，假設沒有或後續補充
                    isPrimary: false,
                  ),
                  const SizedBox(height: 20), // 底部留白
                ],
              ),
            ),
          ],
        ),
      ),
      // 底部導覽列
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF121212),
        selectedItemColor: const Color(0xFF0A58F5), // 選中的藍色
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) {
            _openCamera(context);
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

/// 自訂的選項卡片 Widget
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