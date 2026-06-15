import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 替換成你的 App Logo 或適合的 Icon
              const Icon(Icons.auto_awesome, size: 80, color: Color(0xFF0A58F5)),
              const SizedBox(height: 24),
              const Text(
                'AI Photo Assistant',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                '登入以開始使用智慧攝影與雲端圖庫',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 64),
              
              // 登入按鈕與載入動畫切換
              _isLoading
                  ? const CircularProgressIndicator(color: Color(0xFF0A58F5))
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.g_mobiledata, size: 32, color: Colors.black),
                      label: const Text('使用 Google 帳號登入', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 2,
                      ),
                      onPressed: () async {
                        setState(() => _isLoading = true);
                        final user = await _authService.signInWithGoogle();
                        
                        if (!mounted) return;
                        setState(() => _isLoading = false);
                        
                        if (user == null) {
                          // 如果 user 為 null，代表使用者取消登入或發生錯誤
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('登入已取消或失敗'), backgroundColor: Colors.redAccent),
                          );
                        }
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}