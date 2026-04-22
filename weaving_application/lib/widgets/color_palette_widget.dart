// lib/widgets/color_palette_widget.dart
// Widget bảng màu 6 màu cố định với cluster-based editing
// Người dùng chọn cluster → chọn màu mới → gọi API thay màu

import 'package:flutter/material.dart';
import '../services/weaving_api_service.dart';
import '../utils/app_theme.dart';

class ColorPaletteWidget extends StatefulWidget {
  final List<ClusterInfo> clusters;       // 6 cluster từ backend
  final List<Color> fixedColors;          // 6 màu cố định
  final List<String> colorNames;          // Tên 6 màu (tiếng Việt)
  final Function(int clusterId, int colorIdx) onClusterColorChange;
  final bool isLoading;

  const ColorPaletteWidget({
    super.key,
    required this.clusters,
    required this.fixedColors,
    required this.colorNames,
    required this.onClusterColorChange,
    this.isLoading = false,
  });

  @override
  State<ColorPaletteWidget> createState() => _ColorPaletteWidgetState();
}

class _ColorPaletteWidgetState extends State<ColorPaletteWidget> {
  int? _selectedCluster;  // Cluster đang được chọn để đổi màu

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppTheme.radiusLG,
        gradient: LinearGradient(
          colors: [
            AppTheme.surfaceBg.withValues(alpha: 0.95),
            AppTheme.cardBg.withValues(alpha: 0.95),
          ],
        ),
        boxShadow: AppTheme.softShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.palette_outlined,
                  size: 18, color: AppTheme.accentBlue),
              const SizedBox(width: 6),
              const Text(
                'Bảng Màu',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const Spacer(),
              if (_selectedCluster != null)
                GestureDetector(
                  onTap: () => setState(() => _selectedCluster = null),
                  child: const Icon(Icons.close, size: 18,
                      color: AppTheme.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Chọn cluster để đổi màu',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),

          // ── Cluster list (các màu hiện tại trong ảnh) ─────────────────
          ...widget.clusters
              .where((c) => c.pixelCount > 0)  // Chỉ hiện cluster có pixel
              .map((cluster) => _buildClusterRow(cluster)),

          // ── Color picker (hiện khi đã chọn cluster) ───────────────────
          if (_selectedCluster != null) ...[
            const Divider(height: 20),
            const Text(
              'Chọn màu mới:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            _buildColorPicker(),
          ],
        ],
      ),
    );
  }

  Widget _buildClusterRow(ClusterInfo cluster) {
    final isSelected = _selectedCluster == cluster.id;
    // Parse hex color
    final hexStr = cluster.color.replaceAll('#', '');
    final clusterColor = Color(int.parse('FF$hexStr', radix: 16));

    return GestureDetector(
      onTap: widget.isLoading
          ? null
          : () => setState(() =>
              _selectedCluster = isSelected ? null : cluster.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusSM,
          color: isSelected
              ? AppTheme.accentBlue.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppTheme.accentBlue : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Ô màu hiện tại
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: clusterColor,
                borderRadius: AppTheme.radiusSM,
                border: Border.all(
                  color: AppTheme.textMuted.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: clusterColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Thông tin cluster
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cluster ${cluster.id} — ${cluster.color}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${cluster.percentage.toStringAsFixed(1)}% diện tích '
                    '(${cluster.pixelCount} px)',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Edit icon
            if (isSelected)
              const Icon(Icons.edit, size: 16, color: AppTheme.accentBlue)
            else
              const Icon(Icons.chevron_right, size: 16,
                  color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(
        widget.fixedColors.length,
        (i) => GestureDetector(
          onTap: widget.isLoading
              ? null
              : () {
                  final clusterId = _selectedCluster!;
                  setState(() => _selectedCluster = null);
                  widget.onClusterColorChange(clusterId, i);
                },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.fixedColors[i],
              borderRadius: AppTheme.radiusSM,
              border: Border.all(
                color: widget.fixedColors[i] == Colors.white
                    ? AppTheme.textMuted.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.fixedColors[i].withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Tooltip(
              message: widget.colorNames[i],
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
