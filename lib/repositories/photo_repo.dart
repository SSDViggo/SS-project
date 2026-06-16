import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
// ⭐️ 正確的官方 auth 套件路徑
import 'package:firebase_auth/firebase_auth.dart'; 

/// 一筆照片紀錄：Storage上的圖片URL + 拍攝/編輯時的AI調色參數
class PhotoRecord {
  final String id;
  final String url;
  final DateTime? createdAt;
  final Map<String, dynamic>? enhancements;

  PhotoRecord({
    required this.id,
    required this.url,
    this.createdAt,
    this.enhancements,
  });

  factory PhotoRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    return PhotoRecord(
      id: doc.id,
      url: data['url'] as String? ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
      enhancements: data['enhancements'] as Map<String, dynamic>?,
    );
  }
}

/// 負責把照片上傳到Firebase Storage，並把URL與相關紀錄寫進Firestore。
class PhotoRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw Exception('使用者尚未登入');
    return user.uid;
  }

  /// 上傳一張照片到Storage，並在Firestore建立對應紀錄。
  Future<String> uploadPhoto(File imageFile) async {
    final uid = _uid; 
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
    
    // 實體圖片存在 Storage 的專屬資料夾
    final storageRef = _storage.ref().child('photo-assistant/users/$uid/$fileName');
    
    // 💡 🔥 核心修正：在這裡加上 SettableMetadata，餵飽 Android 底層，防止 NullPointerException 卡死
    await storageRef.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    
    final downloadUrl = await storageRef.getDownloadURL();

    // 將資料庫紀錄寫入統一的 'photos' collection
    await _db.collection('photos').add({
      'url': downloadUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'userId': uid, // 綁定此照片屬於誰
    });

    return downloadUrl;
  }

  Future<void> deletePhoto(String photoId) async {
    debugPrint('deletePhoto: start deleting photoId=$photoId');
    try {
      final docRef = _db.collection('photos').doc(photoId);
      final docSnapshot = await docRef.get();
      
      if (!docSnapshot.exists) {
        throw Exception('找不到該照片的資料庫紀錄');
      }

      final data = docSnapshot.data();
      
      // 確保使用者只能刪除自己的照片
      if (data?['userId'] != _uid) {
        throw Exception('無權刪除此照片');
      }

      final String? imageUrl = data?['url'];

      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final storageRef = _storage.refFromURL(imageUrl);
          debugPrint('deletePhoto: deleting storage file=${storageRef.fullPath}');
          await storageRef.delete();
          debugPrint('deletePhoto: storage file deleted successfully');
        } catch (storageError) {
          debugPrint('Warning: Failed to delete storage file, might not exist: $storageError');
        }
      }

      await docRef.delete();
      debugPrint('deletePhoto: Firestore doc deleted successfully');
    } catch (e, st) {
      debugPrint('deletePhoto failed: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// 依時間新到舊串流目前使用者的所有照片紀錄
  Stream<List<PhotoRecord>> streamPhotos() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]); // 沒登入就回傳空陣列

    return _db
        .collection('photos')
        .where('userId', isEqualTo: uid) 
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => PhotoRecord.fromDoc(doc)).toList());
  }
}