import 'package:flutter/material.dart';
import '../repositories/photo_repo.dart';
import 'ai_edit_screen.dart';

class GalleryScreen extends StatefulWidget {
  final bool isPickerMode;
  const GalleryScreen({super.key, this.isPickerMode = false});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final PhotoRepository _photoRepo = PhotoRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          '我的相簿',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF121212),
      ),
      body: _buildAppPhotosView(),
    );
  }

  /// 僅保留原 App 內部拍攝照片的分頁
  Widget _buildAppPhotosView() {
    return StreamBuilder<List<PhotoRecord>>(
      stream: _photoRepo.streamPhotos(),
      builder: (context, snapshot) {
        // 載入中
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF105BFB)),
          );
        }

        // 錯誤
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.withOpacity(0.6)),
                const SizedBox(height: 16),
                const Text('載入照片失敗', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Text(snapshot.error.toString(), style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ),
          );
        }

        final photos = snapshot.data ?? [];

        if (photos.isEmpty) {
          return _buildEmptyState('相簿中還沒有照片', '使用智慧相機拍攝的照片將會顯示在這裡');
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.0,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return GestureDetector(
                onTap: () {
                  if (widget.isPickerMode) {
                    // 【動線 1】：立刻關閉圖庫，將圖片 URL/路徑 回傳給前一個 Edit 畫面
                    Navigator.of(context).pop(photo.url);
                  } else {
                    // 【動線 2】：正常彈窗預覽，裡面才有「用 AI 編輯」的按鈕
                    _showFirebasePreviewDialog(context, photo);
                  }
                },
                child: Hero(
                  tag: 'firebase_${photo.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF1E1E22),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        photo.url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              color: const Color(0xFF105BFB),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(Icons.image_not_supported, 
                              color: Colors.grey.withOpacity(0.5)),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// ⭐️ 重構後的預覽燈箱：改為底端 AI 編輯與頂端刪除按鈕
  void _showFirebasePreviewDialog(BuildContext context, PhotoRecord photo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 載入 Firebase 圖片原圖
            Image.network(
              photo.url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    color: const Color(0xFF105BFB),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported, 
                        size: 48, color: Colors.red.withOpacity(0.6)),
                      const SizedBox(height: 16),
                      const Text('無法載入圖片', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                );
              },
            ),

            // 右上方關閉按鈕
            Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            // ⭐️ 新增：左上方刪除按鈕
            Positioned(
              top: 8,
              left: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _confirmDelete(context, photo.id),
                ),
              ),
            ),

            // ⭐️ 修改：底部 AI 編輯按鈕（直接導入 AiEditScreen）
            Positioned(
              bottom: 24,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: const Text('用 AI 智能增強', style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: () {
                  Navigator.of(context).pop(); // 先關閉燈箱
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      // 註：如果你的 AiEditScreen 需要 File Path，這裡可能需要丟 photo.url 
                      // 或是先在該頁面做 CacheManager 下載，這裡直接傳入遠端網址
                      builder: (_) => AiEditScreen(imagePath: photo.url), 
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ⭐️ 獨立的刪除確認對話框
  void _confirmDelete(BuildContext dialogContext, String photoId) {
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('確認刪除', style: TextStyle(color: Colors.white)),
        content: const Text('確定要刪除此照片嗎？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // 關閉確認對話框
              Navigator.pop(dialogContext); // 關閉預覽燈箱
              
              try {
                // 呼叫你的 Repository 實作刪除邏輯
                await _photoRepo.deletePhoto(photoId); 
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('照片已成功刪除')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('刪除失敗: $e')),
                );
              }
            },
            child: const Text('確認', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: Colors.grey.withOpacity(0.6), fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}