import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class UnsplashRequestException implements Exception {
  final String message;
  UnsplashRequestException(this.message);

  @override
  String toString() => 'UnsplashRequestException: $message';
}

/// 呼叫Unsplash API，依關鍵詞搜尋一張圖片。
///
/// 這個service本身不做任何"決策"——它是agentic流程裡的「工具(tool)」，
/// 由Gemini決定要搜尋什麼關鍵詞，這個service只負責執行搜尋並回傳結果。
class UnsplashService {
  final bool hasApiKey;

  UnsplashService() : hasApiKey = (dotenv.env['UNSPLASH_ACCESS_KEY'] ?? '').isNotEmpty;

  /// 依關鍵詞搜尋一張圖片，回傳圖片URL（regular尺寸）。
  /// 找不到結果時回傳null。
  Future<String?> searchPhoto(String query) async {
    final accessKey = dotenv.env['UNSPLASH_ACCESS_KEY'] ?? '';
    if (accessKey.isEmpty) {
      throw UnsplashRequestException('找不到UNSPLASH_ACCESS_KEY，請確認.env設定');
    }
 
    final result = await _search(query, accessKey);
    if (result != null) return result;
 
    // fallback：只取前兩個字重試（去掉主體，只留風格描述）
    final words = query.trim().split(' ');
    if (words.length > 2) {
      final shortQuery = words.take(2).join(' ');
      debugPrint('Unsplash fallback: "$query" → "$shortQuery"');
      return await _search(shortQuery, accessKey);
    }
 
    return null;
  }
 
  Future<String?> _search(String query, String accessKey) async {
    final uri = Uri.https('api.unsplash.com', '/search/photos', {
      'query': query,
      'per_page': '1',
      'orientation': 'squarish',
    });
 
    try {
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Client-ID $accessKey'},
      );
 
      if (response.statusCode != 200) {
        throw UnsplashRequestException('HTTP ${response.statusCode}: ${response.body}');
      }
 
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
 
      final urls = results.first['urls'] as Map<String, dynamic>?;
      return urls?['regular'] as String?;
    } catch (e) {
      if (e is UnsplashRequestException) rethrow;
      throw UnsplashRequestException(e.toString());
    }
  }

  /// 依多組關鍵詞搜尋多張圖片（並行請求）。
  /// 個別搜尋失敗會回傳null（不中斷其他搜尋），由呼叫端決定如何處理。
  Future<List<String?>> searchPhotos(List<String> queries) async {
    final futures = queries.map((q) async {
      try {
        return await searchPhoto(q);
      } catch (e) {
        debugPrint('Unsplash搜尋失敗 ("$q"): $e');
        return null;
      }
    });
    return Future.wait(futures);
  }
}