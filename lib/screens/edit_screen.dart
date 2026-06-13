import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';
import '../repositories/photo_repo.dart';
import '../tools/gemini_color_service.dart';
import '../tools/image_processing_service.dart';
import 'library_screen.dart';
import 'package:flutter/foundation.dart' show compute;

/// AI智能增強／編輯畫面。
///
/// [imagePath]：要編輯的照片路徑。若沒有傳入，會嘗試使用
/// [CameraProvider.lastCapturePath]（最近一次拍攝的照片）。
///
/// AI建議流程：
/// 1. 使用者按下「AI 調色」→ [_analyzeColors] 把目前照片送給
///    [GeminiColorService]，**只取得四項調整數值與說明文字**（不會收到任何圖片）。
/// 2. 取得數值後存進[CameraProvider.colorSuggestion]，4個建議卡片
///    會顯示實際數值與說明，使用者可勾選要套用哪些項目。
/// 3. 預覽圖的Color Matrix會即時加總「手動數值」與「已勾選的AI建議數值」。
class EditScreen extends StatefulWidget {
  final String? imagePath;

  const EditScreen({Key? key, this.imagePath}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  bool _isSaving = false;

  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cameraProvider = context.read<CameraProvider>();
      cameraProvider.startEditing(widget.imagePath ?? cameraProvider.lastCapturePath);
    });
  }

  final GeminiColorService _geminiColorService = GeminiColorService();

  Future<void> _analyzeColors(String path) async {
    final cameraProvider = context.read<CameraProvider>();

    if (!_geminiColorService.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到Gemini API Key，請確認.env設定')),
      );
      return;
    }

    cameraProvider.setAnalyzingColor(true);
    try {
      final bytes = await File(path).readAsBytes();
      final suggestion = await _geminiColorService.analyzeColors(bytes);
      if (!mounted) return;
      cameraProvider.setColorSuggestion(suggestion);
    } on GeminiColorRequestException catch (e) {
      debugPrint('Gemini Color API Error: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('連線錯誤，請檢查網路狀態')),
        );
      }
    } on GeminiColorParseException catch (e) {
      debugPrint('Gemini Color Parse Error: ${e.message}');
      debugPrint('Raw response: ${e.rawResponse}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 分析失敗，請再試一次')),
        );
      }
    } finally {
      if (mounted) cameraProvider.setAnalyzingColor(false);
    }
  }

  void _goToLibrary(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LibraryScreen()),
    );
  }

  List<double> _buildPreviewColorMatrix(CameraProvider provider) {
    final brightness = provider.effectiveValue('brightness');
    final sharpness = provider.effectiveValue('sharpness');
    var contrast = provider.effectiveValue('contrast');
    final saturation = provider.effectiveValue('saturation');

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

  /// 套用所有AI建議：
  ///
  /// 目前還沒有真正的影像處理邏輯，先把目前的照片複製一份存成「新照片」，
  /// 並加進圖庫清單，讓「套用」這個動作有實際可見的結果。
  /// 之後要接上真正的影像處理時，只需要把「複製檔案」這一步，
  /// 換成「依照cameraProvider.currentEnhancements/appliedSuggestions
  /// 處理像素後再寫入新檔案」即可，前後的流程（存檔、加入圖庫、提示、返回）不變。
  Future<void> _applyAllSuggestions(BuildContext context, String sourcePath) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'EDIT_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${directory.path}/$fileName';

      final cameraProvider = context.read<CameraProvider>();
      final inputBytes = await File(sourcePath).readAsBytes();
      final outputBytes = await compute(
        processImageBytes,
        ImageProcessingParams(
          bytes: inputBytes,
          brightness: cameraProvider.effectiveValue('brightness'),
          contrast: cameraProvider.effectiveValue('contrast'),
          saturation: cameraProvider.effectiveValue('saturation'),
          sharpness: cameraProvider.effectiveValue('sharpness'),
        ),
      );
      await File(savedPath).writeAsBytes(outputBytes);

      if (!mounted) return;
      cameraProvider.addPhoto(savedPath);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已套用並儲存到圖庫'), backgroundColor: Colors.green),
      );

      // // 連同這次套用的調整參數（Agent決策紀錄）一起上傳
      // final enhancements = {
      //   'brightness': cameraProvider.effectiveValue('brightness'),
      //   'saturation': cameraProvider.effectiveValue('saturation'),
      //   'contrast': cameraProvider.effectiveValue('contrast'),
      //   'sharpness': cameraProvider.effectiveValue('sharpness'),
      // };
      // PhotoRepository()
      //     .uploadPhoto(File(savedPath), enhancements: enhancements)
      //     .catchError((e) {
      //   debugPrint('上傳Firebase失敗: $e');
      // });

      _goToLibrary(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('AI 智能增強'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Consumer<CameraProvider>(
        builder: (context, cameraProvider, _) {
          final path = widget.imagePath ?? cameraProvider.lastCapturePath;

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
                              ? Image.file(
                                  File(path),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        size: 80,
                                        color: Colors.grey[700],
                                      ),
                                    );
                                  },
                                )
                              : ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: cameraProvider.effectiveValue('sharpness') < 0
                                        ? -cameraProvider.effectiveValue('sharpness') / 100 * 5
                                        : 0,
                                    sigmaY: cameraProvider.effectiveValue('sharpness') < 0
                                        ? -cameraProvider.effectiveValue('sharpness') / 100 * 5
                                        : 0,
                                  ),
                                  child: ColorFiltered(
                                    colorFilter: ColorFilter.matrix(
                                      _buildPreviewColorMatrix(cameraProvider),
                                    ),
                                    child: Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Center(
                                          child: Icon(
                                            Icons.broken_image,
                                            size: 80,
                                            color: Colors.grey[700],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                        )
                      else
                        Center(
                          child: Icon(
                            Icons.image,
                            size: 80,
                            color: Colors.grey[700],
                          ),
                        ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: () => setState(() => _showOriginal = !_showOriginal),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _showOriginal ? Icons.visibility_off : Icons.visibility,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showOriginal ? '原圖' : '編輯後',
                                  style: const TextStyle(fontSize: 12),
                                ),
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
                          // AI Suggestions：按下「AI 調色」呼叫API取得真實數值
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      '✨ AI 建議',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: (path == null || cameraProvider.isAnalyzingColor)
                                          ? null
                                          : () => _analyzeColors(path),
                                      icon: cameraProvider.isAnalyzingColor
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.auto_fix_high, size: 18),
                                      label: Text(cameraProvider.isAnalyzingColor ? '分析中...' : 'AI 調色'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _buildEnhancementTile(
                                  icon: Icons.brightness_6,
                                  title: '亮度',
                                  item: cameraProvider.colorSuggestion?.brightness,
                                  enabled: cameraProvider.appliedSuggestions['brightness'] ?? false,
                                  onToggle: (value) {
                                    cameraProvider.toggleSuggestion('brightness', value);
                                  },
                                ),
                                const SizedBox(height: 12),
                                _buildEnhancementTile(
                                  icon: Icons.palette,
                                  title: '飽和度',
                                  item: cameraProvider.colorSuggestion?.saturation,
                                  enabled: cameraProvider.appliedSuggestions['saturation'] ?? false,
                                  onToggle: (value) {
                                    cameraProvider.toggleSuggestion('saturation', value);
                                  },
                                ),
                                const SizedBox(height: 12),
                                _buildEnhancementTile(
                                  icon: Icons.contrast,
                                  title: '對比度',
                                  item: cameraProvider.colorSuggestion?.contrast,
                                  enabled: cameraProvider.appliedSuggestions['contrast'] ?? false,
                                  onToggle: (value) {
                                    cameraProvider.toggleSuggestion('contrast', value);
                                  },
                                ),
                                const SizedBox(height: 12),
                                _buildEnhancementTile(
                                  icon: Icons.details,
                                  title: '銳度',
                                  item: cameraProvider.colorSuggestion?.sharpness,
                                  enabled: cameraProvider.appliedSuggestions['sharpness'] ?? false,
                                  onToggle: (value) {
                                    cameraProvider.toggleSuggestion('sharpness', value);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Enhancement Controls
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '手動調整',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _buildSliderControl(
                                  label: '亮度',
                                  value: cameraProvider.currentEnhancements['brightness'] ?? 0.0,
                                  onChanged: (value) {
                                    cameraProvider.updateEnhancement('brightness', value);
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildSliderControl(
                                  label: '飽和度',
                                  value: cameraProvider.currentEnhancements['saturation'] ?? 0.0,
                                  onChanged: (value) {
                                    cameraProvider.updateEnhancement('saturation', value);
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildSliderControl(
                                  label: '對比度',
                                  value: cameraProvider.currentEnhancements['contrast'] ?? 0.0,
                                  onChanged: (value) {
                                    cameraProvider.updateEnhancement('contrast', value);
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildSliderControl(
                                  label: '銳度',
                                  value: cameraProvider.currentEnhancements['sharpness'] ?? 0.0,
                                  onChanged: (value) {
                                    cameraProvider.updateEnhancement('sharpness', value);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Apply Button
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0066FF),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: (path == null || _isSaving)
                                    ? null
                                    : () => _applyAllSuggestions(context, path),
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.0,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.auto_awesome),
                                          SizedBox(width: 8),
                                          Text('套用所有 AI 建議'),
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
        },
      ),
    );
  }

  Widget _buildEnhancementTile({
    required IconData icon,
    required String title,
    required ColorAdjustmentItem? item,
    required bool enabled,
    required Function(bool) onToggle,
  }) {
    final hasItem = item != null;
    final value = item?.value ?? 0;
    final subtitle = hasItem
        ? '${value > 0 ? '+' : ''}${value.round()}% · ${item!.reason}'
        : '尚未分析，請按上方「AI 調色」';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2a2a2a),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          Checkbox(
            value: enabled,
            onChanged: hasItem
                ? (value) {
                    onToggle(value ?? false);
                  }
                : null,
            fillColor: MaterialStateProperty.resolveWith((states) {
              return const Color(0xFF0066FF);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              '${value.round()}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
            ),
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