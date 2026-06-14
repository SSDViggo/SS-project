import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart'; // ⭐️ 引入裝置相簿套件
import '../providers/camera_provider.dart';
import 'ai_edit_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<AssetEntity> _devicePhotos = []; // 儲存從手機撈出來的照片物件
  bool _isLoadingDevicePhotos = false;
  bool _hasDevicePermission = false;

  @override
  void initState() {
    super.initState();
    // 頁面初始化時，嘗試載入一次手機相簿
    _loadDevicePhotos();
  }

  /// ⭐️ 核心邏輯：向手機請求權限並讀取系統圖庫
  Future<void> _loadDevicePhotos() async {
    setState(() => _isLoadingDevicePhotos = true);

    // 1. 請求相簿存取權限
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    
    if (ps.isAuth) {
      setState(() => _hasDevicePermission = true);
      
      // 2. 撈取手機裡所有的相簿（Recent 是最常見的「最近項目」）
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image, // 我們只需要圖片
      );

      if (albums.isNotEmpty) {
        // 3. 從最近的相簿中撈取前 100 張照片（可依需求調整數量）
        List<AssetEntity> photos = await albums[0].getAssetListRange(
          start: 0,
          end: 100,
        );
        
        setState(() {
          _devicePhotos = photos;
        });
      }
    } else {
      setState(() => _hasDevicePermission = false);
    }

    setState(() => _isLoadingDevicePhotos = false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // ⭐️ 分成兩個分頁
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text(
            '我的相簿',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: const Color(0xFF121212),
          // ⭐️ 導覽列下方加入 TabBar 切換
          bottom: const TabBar(
            indicatorColor: Color(0xFF105BFB),
            labelColor: Color(0xFF105BFB),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'App 拍攝'),
              Tab(text: '手機相簿'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // 【分頁一】：原本的 App 內部拍攝照片
            _buildAppPhotosView(),

            // 【分頁二】：手機系統圖庫照片
            _buildDevicePhotosView(),
          ],
        ),
      ),
    );
  }

  /// 內建分頁一：原本的 App 內部相簿
  Widget _buildAppPhotosView() {
    return Consumer<CameraProvider>(
      builder: (context, cameraProvider, child) {
        final List<String> photoPaths = cameraProvider.capturedPhotos;

        if (photoPaths.isEmpty) {
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
            itemCount: photoPaths.length,
            itemBuilder: (context, index) {
              final String path = photoPaths[index];
              return GestureDetector(
                onTap: () => _showLocalPreviewDialog(context, path),
                child: Hero(
                  tag: 'local_$path',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF1E1E22),
                      border: Border.all(color: Colors.white12, width: 1),
                      image: DecorationImage(
                        image: FileImage(File(path)),
                        fit: BoxFit.cover,
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

  /// ⭐️ 內建分頁二：手機系統相簿
  Widget _buildDevicePhotosView() {
    if (_isLoadingDevicePhotos) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF105BFB)));
    }

    if (!_hasDevicePermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('需要相簿存取權限才能查看手機照片', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF105BFB)),
              onPressed: _loadDevicePhotos,
              child: const Text('授權存取', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_devicePhotos.isEmpty) {
      return _buildEmptyState('手機相簿中沒有照片', '去拍幾張照片試試看吧！');
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
        itemCount: _devicePhotos.length,
        itemBuilder: (context, index) {
          final AssetEntity asset = _devicePhotos[index];
          
          // ⭐️ 使用 AssetEntityImage 渲染，photo_manager 會自動處理原生高效率縮圖快取
          return GestureDetector(
            onTap: () => _showDevicePreviewDialog(context, asset),
            child: Hero(
              tag: 'device_${asset.id}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: const Color(0xFF1E1E22),
                  child: AssetEntityImage(
                    asset,
                    isOriginal: false, // 使用縮圖，效能極高
                    thumbnailSize: const ThumbnailSize.square(200),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        },
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

  // 本地 App 照片的放大預覽
  // 本地 App 照片的放大預覽
  void _showLocalPreviewDialog(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.file(File(path), fit: BoxFit.contain),
            _buildDialogCloseButton(context),
            
            // ⭐️ 新增：底部 AI 編輯按鈕
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
                      // 把這張照片的路徑傳給 AiEditScreen
                      builder: (_) => AiEditScreen(imagePath: path), 
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

  // ⭐️ 手機系統照片的放大預覽
  // ⭐️ 手機系統照片的放大預覽
  void _showDevicePreviewDialog(BuildContext context, AssetEntity asset) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 載入原圖顯示
            Image(
              image: AssetEntityImageProvider(
                asset,
                isOriginal: true, // 載入原圖
              ),
              fit: BoxFit.contain,
            ),
            _buildDialogCloseButton(context),

            // ⭐️ 新增：底部 AI 編輯按鈕
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
                onPressed: () async {
                  // 因為手機照片是 AssetEntity，我們要先把它轉回一般的 File 才能給你的 AI 模組用
                  final file = await asset.file;
                  
                  if (!context.mounted) return;
                  
                  if (file != null) {
                    Navigator.of(context).pop(); // 關閉燈箱
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AiEditScreen(imagePath: file.path),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('無法讀取此照片')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildDialogCloseButton(BuildContext context) {
    return Positioned(
      top: 8, right: 8,
      child: CircleAvatar(
        backgroundColor: Colors.black54,
        child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}