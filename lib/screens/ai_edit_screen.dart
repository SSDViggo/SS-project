import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';
import '../tools/gemini_style_service.dart';
import '../tools/gemini_style_transfer_service.dart';
import '../tools/unsplash_service.dart';
import '../tools/image_processing_service.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import '../repositories/style_memory_repo.dart';
import '../repositories/photo_repo.dart';
import 'dart:typed_data'; // ⭐️ 引入 Uint8List 支援

/// AI智能增強／編輯畫面（agentic版本）。
class AiEditScreen extends StatefulWidget {
  final String? imagePath;

  const AiEditScreen({Key? key, this.imagePath}) : super(key: key);

  @override
  State<AiEditScreen> createState() => _AiEditScreenState();
}

enum _Phase {
  noPhoto,
  loadingStyles,
  selectingStyle,
  analyzingTransfer,
  editing,
  error,
}

class _StyleChoice {
  final StyleOption option;
  final String? imageUrl;

  _StyleChoice({required this.option, this.imageUrl});
}

class _AiEditScreenState extends State<AiEditScreen> {
  final GeminiStyleService _geminiStyleService = GeminiStyleService();
  final GeminiStyleTransferService _styleTransferService = GeminiStyleTransferService();
  final UnsplashService _unsplashService = UnsplashService();
  final StyleMemoryRepository _memoryRepo = StyleMemoryRepository();

  _Phase _phase = _Phase.loadingStyles;
  String? _errorMessage;

  List<_StyleChoice> _styleChoices = [];
  int? _selectedStyleIndex;

  bool _showOriginal = false;
  bool _isSaving = false;
  String? _pickedImagePath;

  /// ⭐️ 修改路徑獲取邏輯：優先使用挑選的照片，其次是 widget 傳入，最後才是相機拍攝
  String? get _path => _pickedImagePath ?? widget.imagePath ?? context.read<CameraProvider>().lastCapturePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initEditor();
    });
  }

  void _initEditor() {
    final path = _path;
    if (path != null) {
      final cameraProvider = context.read<CameraProvider>();
      cameraProvider.startEditing(path);
      _startStyleAnalysis();
    } else {
      setState(() => _phase = _Phase.noPhoto);
    }
  }

  /// ⭐️ 輔助方法：動態判斷該使用 Image.network 還是 Image.file 進行顯示
  Widget _buildPreviewImage(String path, {BoxFit fit = BoxFit.cover, double? height, double? width}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(path, fit: fit, height: height, width: width);
    } else {
      return Image.file(File(path), fit: fit, height: height, width: width);
    }
  }

  /// 步驟1-2：Gemini決定風格方向 → 搜尋參考圖
  Future<void> _startStyleAnalysis() async {
    final path = _path;
    
    if (path == null) {
      setState(() => _phase = _Phase.noPhoto);
      return;
    }

    if (!_geminiStyleService.hasApiKey) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = '找不到Gemini API Key，請確認.env設定';
      });
      return;
    }

    setState(() {
      _phase = _Phase.loadingStyles;
      _errorMessage = null;
    });

    try {
      // ⭐️ 修復：分流讀取遠端 URL 或是 本地 File 的 bytes
      final Uint8List bytes;
      if (path.startsWith('http://') || path.startsWith('https://')) {
        debugPrint('_startStyleAnalysis: 偵測到遠端網路圖片，開始下載... $path');
        final response = await http.get(Uri.parse(path));
        if (response.statusCode == 200) {
          bytes = response.bodyBytes;
        } else {
          throw Exception('下載網路圖片失敗，HTTP 狀態碼: ${response.statusCode}');
        }
      } else {
        bytes = await File(path).readAsBytes();
      }

      // [Memory] 先讀取使用者歷史風格偏好
      final recentMemory = await _memoryRepo.loadRecent();
      final memoryContext = StyleMemoryRepository.toPromptContext(recentMemory);
      debugPrint('===讀取到${recentMemory.length}筆風格記憶===');

      // [Reasoning 1] AI自主決定3種不同風格方向
      final styles = await _geminiStyleService.suggestStyles(bytes);

      // [Tool Using] 用AI決定的關鍵詞，呼叫Unsplash搜尋參考圖
      final urls = await _unsplashService.searchPhotos(
        styles.map((s) => s.searchQuery).toList(),
      );

      if (!mounted) return;
      setState(() {
        _styleChoices = List.generate(
          styles.length,
          (i) => _StyleChoice(option: styles[i], imageUrl: urls[i]),
        );
        _phase = _Phase.selectingStyle;
      });
    } on GeminiStyleRequestException catch (e) {
      debugPrint('Gemini Style API Error: ${e.message}');
      _setError('連線錯誤，請檢查網路狀態');
    } on GeminiStyleParseException catch (e) {
      debugPrint('Gemini Style Parse Error: ${e.message}');
      debugPrint('Raw response: ${e.rawResponse}');
      _setError('AI 分析失敗，請再試一次');
    } catch (e) {
      debugPrint('Style analysis error: $e');
      _setError('發生未知錯誤，請再試一次');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = message;
    });
  }

  /// 步驟4：使用者選了某張參考圖 → AI比較原圖與參考圖 → 輸出調色數值
  Future<void> _selectStyle(int index) async {
    final path = _path;
    final choice = _styleChoices[index];
    if (path == null || choice.imageUrl == null) return;

    setState(() {
      _selectedStyleIndex = index;
      _phase = _Phase.analyzingTransfer;
    });

    try {
      // ⭐️ 修復：分流讀取遠端 URL 或是 本地 File 的原圖 bytes
      final Uint8List originalBytes;
      if (path.startsWith('http://') || path.startsWith('https://')) {
        debugPrint('_selectStyle: 偵測到原圖為遠端網路圖片，開始下載... $path');
        final response = await http.get(Uri.parse(path));
        if (response.statusCode == 200) {
          originalBytes = response.bodyBytes;
        } else {
          throw Exception('下載原圖網路圖片失敗，HTTP 狀態碼: ${response.statusCode}');
        }
      } else {
        originalBytes = await File(path).readAsBytes();
      }

      final response = await http.get(Uri.parse(choice.imageUrl!));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final referenceBytes = response.bodyBytes;

      // [Reasoning 2] AI比較兩張圖，輸出調色數值
      final suggestion = await _styleTransferService.analyze(
        originalImageBytes: originalBytes,
        referenceImageBytes: referenceBytes,
      );

      debugPrint('===StyleTransfer建議: '
          'brightness=${suggestion.brightness.value}(${suggestion.brightness.reason}), '
          'saturation=${suggestion.saturation.value}(${suggestion.saturation.reason}), '
          'contrast=${suggestion.contrast.value}(${suggestion.contrast.reason}), '
          'sharpness=${suggestion.sharpness.value}(${suggestion.sharpness.reason})===');

      if (!mounted) return;
      final cameraProvider = context.read<CameraProvider>();
      cameraProvider.setColorSuggestion(suggestion);
      debugPrint('===setColorSuggestion後currentEnhancements: '
          '${cameraProvider.currentEnhancements}===');
      setState(() => _phase = _Phase.editing);
    } on GeminiStyleTransferRequestException catch (e) {
      debugPrint('Gemini Style Transfer API Error: ${e.message}');
      _setError('連線錯誤，請檢查網路狀態');
    } on GeminiStyleTransferParseException catch (e) {
      debugPrint('Gemini Style Transfer Parse Error: ${e.message}');
      debugPrint('Raw response: ${e.rawResponse}');
      _setError('AI 分析失敗，請再試一次');
    } catch (e) {
      debugPrint('Style transfer error: $e');
      _setError('發生未知錯誤，請再試一次');
    }
  }

  /// 跳過風格選擇，直接進入手動調整——重置所有數值為0（從零開始調整）
  void _skipToManualEditing() {
    context.read<CameraProvider>().resetEnhancements();
    setState(() => _phase = _Phase.editing);
  }

  void _goToLibrary(BuildContext context, {bool isAfterSave = false}) {
    if (isAfterSave) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GalleryScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GalleryScreen()),
      );
    }
  }

  List<double> _buildPreviewColorMatrix(CameraProvider provider) {
    final brightness = provider.currentEnhancements['brightness'] ?? 0.0;
    final sharpness = provider.currentEnhancements['sharpness'] ?? 0.0;
    var contrast = provider.currentEnhancements['contrast'] ?? 0.0;
    final saturation = provider.currentEnhancements['saturation'] ?? 0.0;

    if (sharpness > 0) contrast += sharpness * 0.3;

    final brightnessOffset = (brightness / 100) * 255;
    final contrastFactor = (1 + contrast / 100).clamp(0.0, 3.0);
    final sat = (1 + saturation / 100).clamp(0.0, 2.0);

    const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
    final invSat = 1 - sat;
    final translate = 128 * (1 - contrastFactor) + brightnessOffset;

    return <double>[
      (lumR * invSat + sat) * contrastFactor, (lumG * invSat) * contrastFactor, (lumB * invSat) * contrastFactor, 0, translate,
      (lumR * invSat) * contrastFactor, (lumG * invSat + sat) * contrastFactor, (lumB * invSat) * contrastFactor, 0, translate,
      (lumR * invSat) * contrastFactor, (lumG * invSat) * contrastFactor, (lumB * invSat + sat) * contrastFactor, 0, translate,
      0, 0, 0, 1, 0,
    ];
  }

  Future<void> _applyAndSave(String sourcePath, CameraProvider cameraProvider) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'EDIT_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';

      // ⭐️ 修復：如果要套用像素級儲存，也需要先下載網路原圖
      final Uint8List inputBytes;
      if (sourcePath.startsWith('http://') || sourcePath.startsWith('https://')) {
        final response = await http.get(Uri.parse(sourcePath));
        if (response.statusCode == 200) {
          inputBytes = response.bodyBytes;
        } else {
          throw Exception('儲存時下載網路圖片失敗');
        }
      } else {
        inputBytes = await File(sourcePath).readAsBytes();
      }

      final outputBytes = await compute(
        processImageBytes,
        ImageProcessingParams(
          bytes: inputBytes,
          brightness: cameraProvider.currentEnhancements['brightness'] ?? 0.0,
          contrast: cameraProvider.currentEnhancements['contrast'] ?? 0.0,
          saturation: cameraProvider.currentEnhancements['saturation'] ?? 0.0,
          sharpness: cameraProvider.currentEnhancements['sharpness'] ?? 0.0,
        ),
      );
      await File(savedPath).writeAsBytes(outputBytes);

      if (!mounted) return;
      cameraProvider.addPhoto(savedPath);

      final photoRepo = PhotoRepository();
      debugPrint('takePicture: uploading file to Firebase');
      final uploadedUrl = await photoRepo.uploadPhoto(File(savedPath));
      debugPrint('takePicture: Firebase upload successful: $uploadedUrl');
      
      final enhancements = {
        'brightness': cameraProvider.currentEnhancements['brightness'] ?? 0.0,
        'saturation': cameraProvider.currentEnhancements['saturation'] ?? 0.0,
        'contrast': cameraProvider.currentEnhancements['contrast'] ?? 0.0,
        'sharpness': cameraProvider.currentEnhancements['sharpness'] ?? 0.0,
      };

      if (_selectedStyleIndex != null &&
          _selectedStyleIndex! < _styleChoices.length) {
        final chosen = _styleChoices[_selectedStyleIndex!];
        _memoryRepo.save(StyleMemoryEntry(
          sceneFeatures: chosen.option.searchQuery,
          chosenStyleLabel: chosen.option.label,
          chosenStyleQuery: chosen.option.searchQuery,
          finalAdjustments: Map<String, double>.from(enhancements),
          timestamp: DateTime.now(),
        )).catchError((e) {
          debugPrint('寫入風格記憶失敗: $e');
        });
        debugPrint('===風格記憶已寫入: ${chosen.option.label}===');
      }

      _goToLibrary(context, isAfterSave: true);
      
    } catch (e) {
      debugPrint('套用編輯失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('儲存失敗，請再試一次'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _shouldInterceptBack => _phase == _Phase.editing && _styleChoices.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_shouldInterceptBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _selectedStyleIndex = null;
          _phase = _Phase.selectingStyle;
        });
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('AI 智能增強'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_shouldInterceptBack) {
                setState(() {
                  _selectedStyleIndex = null;
                  _phase = _Phase.selectingStyle;
                });
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
        ),
        body: Consumer<CameraProvider>(
          builder: (context, cameraProvider, _) {
            switch (_phase) {
              case _Phase.noPhoto:
                return _buildNoPhoto();
              case _Phase.loadingStyles:
                return _buildLoading('AI 正在分析照片，尋找適合的風格...');
              case _Phase.error:
                return _buildError();
              case _Phase.selectingStyle:
                return _buildStyleSelection();
              case _Phase.analyzingTransfer:
                return _buildLoading('AI 正在比對風格、計算調色參數...');
              case _Phase.editing:
                return _buildEditingView(cameraProvider);
            }
          },
        ),
      ),
    );
  }

  Widget _buildNoPhoto() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_outlined, color: Colors.grey[600], size: 48),
            const SizedBox(height: 16),
            Text('還沒有可以編輯的照片', style: TextStyle(color: Colors.grey[300], fontSize: 16)),
            const SizedBox(height: 4),
            Text('先拍一張照片，或從圖庫選一張', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('去拍照'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const FullScreenCameraScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('去圖庫選照片'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  final String? selectedPath = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const GalleryScreen(isPickerMode: true),
                    ),
                  );

                  if (selectedPath != null && mounted) {
                    setState(() {
                      _pickedImagePath = selectedPath;
                    });
                    _initEditor();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage ?? '發生錯誤', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _startStyleAnalysis, child: const Text('重試')),
            const SizedBox(height: 8),
            TextButton(onPressed: _skipToManualEditing, child: const Text('跳過，直接手動調整')),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleSelection() {
    final path = _path;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildPreviewImage(
                path,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            '✨ AI 為這張照片找了三種風格方向',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '選一張你喜歡的風格，AI會分析差異並調整你的照片',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          ..._styleChoices.asMap().entries.map((entry) {
            final index = entry.key;
            final choice = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildStyleCard(index, choice),
            );
          }),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _skipToManualEditing,
              child: const Text('跳過，直接手動調整'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleCard(int index, _StyleChoice choice) {
    final loading = _phase == _Phase.analyzingTransfer && _selectedStyleIndex == index;

    return Material(
      color: const Color(0xFF2a2a2a),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: choice.imageUrl == null ? null : () => _selectStyle(index),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: choice.imageUrl != null
                    ? Image.network(
                        choice.imageUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[800],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey[800],
                        child: const Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  choice.option.label,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              if (loading)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else
                const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditingView(CameraProvider cameraProvider) {
    final path = _path;

    return Column(
      children: [
        GestureDetector(
          onTap: () => _goToLibrary(context),
          child: Container(
            height: 200,
            width: double.infinity,
            color: Colors.black,
            child: Stack(
              children: [
                if (path != null)
                  Positioned.fill(
                    child: _showOriginal
                        ? _buildPreviewImage(path, fit: BoxFit.cover)
                        : ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: (cameraProvider.currentEnhancements['sharpness'] ?? 0.0) < 0
                                  ? -(cameraProvider.currentEnhancements['sharpness'] ?? 0.0) / 100 * 5
                                  : 0,
                              sigmaY: (cameraProvider.currentEnhancements['sharpness'] ?? 0.0) < 0
                                  ? -(cameraProvider.currentEnhancements['sharpness'] ?? 0.0) / 100 * 5
                                  : 0,
                            ),
                            child: ColorFiltered(
                              colorFilter: ColorFilter.matrix(_buildPreviewColorMatrix(cameraProvider)),
                              child: _buildPreviewImage(path, fit: BoxFit.cover),
                            ),
                          ),
                  )
                else
                  Center(child: Icon(Icons.image, size: 80, color: Colors.grey[700])),
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => setState(() => _showOriginal = !_showOriginal),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        children: [
                          Icon(_showOriginal ? Icons.visibility_off : Icons.visibility, size: 14),
                          const SizedBox(width: 4),
                          Text(_showOriginal ? '原圖' : '編輯後', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('調整', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 8),
                        _buildSliderControl(
                          label: '亮度',
                          value: cameraProvider.currentEnhancements['brightness'] ?? 0.0,
                          reason: cameraProvider.colorSuggestion?.brightness.reason,
                          onChanged: (v) => cameraProvider.updateEnhancement('brightness', v),
                        ),
                        const SizedBox(height: 16),
                        _buildSliderControl(
                          label: '飽和度',
                          value: cameraProvider.currentEnhancements['saturation'] ?? 0.0,
                          reason: cameraProvider.colorSuggestion?.saturation.reason,
                          onChanged: (v) => cameraProvider.updateEnhancement('saturation', v),
                        ),
                        const SizedBox(height: 16),
                        _buildSliderControl(
                          label: '對比度',
                          value: cameraProvider.currentEnhancements['contrast'] ?? 0.0,
                          reason: cameraProvider.colorSuggestion?.contrast.reason,
                          onChanged: (v) => cameraProvider.updateEnhancement('contrast', v),
                        ),
                        const SizedBox(height: 16),
                        _buildSliderControl(
                          label: '銳度',
                          value: cameraProvider.currentEnhancements['sharpness'] ?? 0.0,
                          reason: cameraProvider.colorSuggestion?.sharpness.reason,
                          onChanged: (v) => cameraProvider.updateEnhancement('sharpness', v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0066FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: (path == null || _isSaving) ? null : () => _applyAndSave(path, cameraProvider),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.auto_awesome),
                                  SizedBox(width: 8),
                                  Text('套用並儲存'),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    String? reason,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            Text('${value.round()}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue)),
          ],
        ),
        if (reason != null) ...[
          const SizedBox(height: 2),
          Text('✨ $reason', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ],
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            activeTrackColor: const Color(0xFF0066FF),
            inactiveTrackColor: Colors.grey[700],
          ),
          child: Slider(
            value: value,
            min: -100,
            max: 100,
            divisions: 200,
            label: '${value.round()}%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}