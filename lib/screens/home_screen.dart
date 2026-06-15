import 'package:flutter/material.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();

  void _logout() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF2a2a2a),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            const Text(
                              'AI 攝影助手',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '您的智能攝影伴侶\n完美構圖和專業編輯',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'logout') {
                                _logout();
                              }
                            },
                            itemBuilder: (BuildContext context) => [
                              const PopupMenuItem<String>(
                                value: 'logout',
                                child: Row(
                                  children: [
                                    Icon(Icons.logout, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('登出'),
                                  ],
                                ),
                              ),
                            ],
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Smart Camera Card
                  FeatureCard(
                    icon: Icons.camera_alt,
                    title: '智能相機',
                    description: '實時 AI 指導，\n構圖網格和水平線檢測',
                    backgroundColor: const Color(0xFF0066FF),
                    onTap: () {
                      // Navigate to camera screen
                    },
                  ),
                  const SizedBox(height: 16),
                  // AI Enhancements Card
                  FeatureCard(
                    icon: Icons.auto_awesome,
                    title: 'AI 增強',
                    description: '智能後期處理建議\n和手動控制',
                    backgroundColor: const Color(0xFF2a2a2a),
                    onTap: () {
                      // Navigate to edit screen
                    },
                  ),
                  const SizedBox(height: 16),
                  // Composition Library Card
                  FeatureCard(
                    icon: Icons.grid_3x3,
                    title: '構圖庫',
                    description: '學習專業構圖技巧\n和最佳實踐',
                    backgroundColor: const Color(0xFF2a2a2a),
                    onTap: () {
                      // Navigate to library screen
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color backgroundColor;
  final VoidCallback onTap;

  const FeatureCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.description,
    required this.backgroundColor,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: backgroundColor == const Color(0xFF0066FF)
              ? null
              : Border.all(
                  color: Colors.grey[700]!,
                  width: 1,
                ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
