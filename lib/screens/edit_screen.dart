import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({Key? key}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('AI 智能增強'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Handle back
          },
        ),
      ),
      body: Consumer<CameraProvider>(
        builder: (context, cameraProvider, _) {
          return SingleChildScrollView(
            child: Column(
              children: [
                // Preview Image
                Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.black,
                  child: Stack(
                    children: [
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check, size: 14),
                              SizedBox(width: 4),
                              Text('編輯前後',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // AI Suggestions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✨ AI 建議',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancementTile(
                        icon: Icons.brightness_6,
                        title: '增加照度',
                        value: '+10%',
                        enabled: false,
                        onToggle: (value) {
                          cameraProvider.updateEnhancement('brightness', value);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildEnhancementTile(
                        icon: Icons.palette,
                        title: '飽和度調整',
                        value: '強烈多彩',
                        enabled: false,
                        onToggle: (value) {
                          cameraProvider.updateEnhancement('saturation', value);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildEnhancementTile(
                        icon: Icons.contrast,
                        title: '對比度提升',
                        value: '正常化',
                        enabled: false,
                        onToggle: (value) {
                          cameraProvider.updateEnhancement('contrast', value);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildEnhancementTile(
                        icon: Icons.details,
                        title: '銳度提升',
                        value: '+8% 彩色銳化',
                        enabled: false,
                        onToggle: (value) {
                          cameraProvider.updateEnhancement('sharpness', value);
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
                        value: cameraProvider.currentEnhancements['brightness'] ?? 0,
                        onChanged: (value) {
                          cameraProvider.updateEnhancement('brightness', value);
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildSliderControl(
                        label: '飽和度',
                        value: cameraProvider.currentEnhancements['saturation'] ?? 0,
                        onChanged: (value) {
                          cameraProvider.updateEnhancement('saturation', value);
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildSliderControl(
                        label: '對比度',
                        value: cameraProvider.currentEnhancements['contrast'] ?? 0,
                        onChanged: (value) {
                          cameraProvider.updateEnhancement('contrast', value);
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildSliderControl(
                        label: '銳度',
                        value: cameraProvider.currentEnhancements['sharpness'] ?? 0,
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
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('編輯已應用'),
                            duration: Duration(milliseconds: 500),
                          ),
                        );
                      },
                      child: const Row(
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
          );
        },
      ),
    );
  }

  Widget _buildEnhancementTile({
    required IconData icon,
    required String title,
    required String value,
    required bool enabled,
    required Function(bool) onToggle,
  }) {
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
                  value,
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
            onChanged: (value) {
              onToggle(value ?? false);
            },
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
              '${value.toStringAsFixed(0)}%',
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
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
