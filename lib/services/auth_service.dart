import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // ⭐️ V7 重大改變 1：改成使用單例 .instance
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance; 

  bool _isInitialized = false;

  // ⭐️ V7 重大改變 2：必須手動呼叫初始化
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await _googleSignIn.initialize();
      _isInitialized = true;
    }
  }

  // 取得當前使用者
  User? get currentUser => _auth.currentUser;

  // 監聽登入狀態變化
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Google 登入邏輯
  Future<User?> signInWithGoogle() async {
    try {
      await _ensureInitialized(); // 使用前確保已初始化

      // ⭐️ V7 重大改變 3：signIn() 變成了 authenticate()
      final GoogleSignInAccount? googleUser = await _googleSignIn.authenticate();
      if (googleUser == null) return null; // 使用者取消登入

      // ⭐️ V7 重大改變 4：認證(Identity)與授權(Authorization)被拆開了
      // 必須透過 authorizationClient 來取得 accessToken
      final clientAuth = await googleUser.authorizationClient.authorizeScopes(['email', 'profile']);

      // 建立 Firebase 憑證 (注意 idToken 和 accessToken 現在來源不同)
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleUser.authentication.idToken, // 從認證端取得
        accessToken: clientAuth.accessToken,        // 從授權端取得
      );

      // 使用憑證登入 Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      debugPrint('Google 登入失敗: $e');
      return null;
    }
  }

  // 登出邏輯
  Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}