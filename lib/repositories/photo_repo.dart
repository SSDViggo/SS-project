import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// 暫時的固定使用者ID（專案目前沒有登入機制）。
/// 之後接上登入系統後，改成從auth取得實際userId即可。
const String kDeviceUserId = 'demo_user';

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

  CollectionReference<Map<String, dynamic>> get _collection => _db
      .collection('apps/photo-assistant/users')
      .doc(kDeviceUserId)
      .collection('photos');

  /// 上傳一張照片到Storage，並在Firestore建立對應紀錄。
  /// [enhancements]可選，存放這張照片套用的AI調色參數（決策紀錄）。
  /// 回傳上傳後的圖片URL。
  Future<String> uploadPhoto(File file, {Map<String, dynamic>? enhancements}) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}';
    final ref = _storage.ref('photo-assistant/$kDeviceUserId/$fileName');
    debugPrint('uploadPhoto: storage path=${ref.fullPath}');

    try {
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final snapshot = await uploadTask;
      debugPrint('uploadPhoto: upload completed, bytesTransferred=${snapshot.bytesTransferred}, totalBytes=${snapshot.totalBytes}');

      final url = await ref.getDownloadURL();
      debugPrint('uploadPhoto: download URL=$url');

      await _collection.add({
        'url': url,
        'createdAt': FieldValue.serverTimestamp(),
        if (enhancements != null) 'enhancements': enhancements,
      });
      debugPrint('uploadPhoto: Firestore record added');

      return url;
    } catch (e, st) {
      debugPrint('uploadPhoto failed: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  Future<void> deletePhoto(String photoId) async {
    debugPrint('deletePhoto: start deleting photoId=$photoId');
    try {
      // 1. 先從 Firestore 撈出這筆紀錄，取得圖片的 Storage URL
      final docSnapshot = await _collection.doc(photoId).get();
      if (!docSnapshot.exists) {
        throw Exception('找不到該照片的資料庫紀錄');
      }

      final data = docSnapshot.data();
      final String? imageUrl = data?['url'];

      // 2. 如果 URL 存在，先去 Firebase Storage 刪除實體檔案
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          // 利用 refFromURL 直接定位到 Storage 的實體檔案位置
          final storageRef = _storage.refFromURL(imageUrl);
          debugPrint('deletePhoto: deleting storage file=${storageRef.fullPath}');
          await storageRef.delete();
          debugPrint('deletePhoto: storage file deleted successfully');
        } catch (storageError) {
          // 預防萬一：若 Storage 檔案已被手動刪除或找不到，記錄下來，但仍繼續刪除資料庫紀錄
          debugPrint('Warning: Failed to delete storage file, might not exist: $storageError');
        }
      }

      // 3. 刪除 Firestore 中的紀錄
      await _collection.doc(photoId).delete();
      debugPrint('deletePhoto: Firestore doc deleted successfully');
    } catch (e, st) {
      debugPrint('deletePhoto failed: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// 依時間新到舊串流目前使用者的所有照片紀錄
  Stream<List<PhotoRecord>> streamPhotos() {
    return _collection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(PhotoRecord.fromDoc).toList());
  }
}