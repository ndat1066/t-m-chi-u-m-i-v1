// lib/widgets/led_panel_widget.dart
// Widget hiển thị 31 LED tương ứng 31 lever
// - LED sáng (vàng): lever cần kéo (giá trị = 1)
// - LED tắt (xám): lever giữ nguyên (giá trị = 0)
// - Người dùng có thể chuyển hàng để xem preview

import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class LedPanelWidget extends StatelessWidget {
  final List<List<int>> matrix;   // Ma trận điều khiển đầy đủ
  final int currentRow;           // Hàng đang hiển thị (0-indexed)
  final ValueChanged<int> onRowChange; // Callback khi đổi hàng

  const LedPanelWidget({
    super.key,
    required this.matrix,
    required this.currentRow,
    required this.onRowChange,
  });

  @override
  Widget build(BuildContext context) {
    if (matrix.isEmpty) return const SizedBox.shrink();

    // Lấy hàng hiện tại, đảm bảo đủ 31 phần tử
    final row = currentRow < matrix.length ? matrix[currentRow] : <int>[];
    final ledStates = List.generate(
      31,
      (i) => i < row.length ? row[i] == 1 : false,
    );
    final activeCount = ledStates.where((s) => s).length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppTheme.radiusLG,
        color: const Color(0xFF0F1923),  // Nền tối để LED nổi bật
        boxShadow: AppTheme.softShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeCount > 0
                      ? AppTheme.accentYellow
                      : AppTheme.textMuted,
                  boxShadow: activeCount > 0
                      ? [BoxShadow(
                          color: AppTheme.accentYellow.withValues(alpha: 0.6),
                          blurRadius: 8,
                        )]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LED Panel — 31 Lever',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              // Badge số lever đang bật
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentYellow.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.accentYellow.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '$activeCount bật',
                  style: const TextStyle(
                    color: AppTheme.accentYellow,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Hàng ${currentRow + 1} / ${matrix.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),

          // ── LED Grid (31 đèn, 2 hàng 16+15 hoặc flex wrap) ──────────
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: List.generate(31, (i) => _buildLedItem(i, ledStates[i])),
          ),

          const SizedBox(height: 14),

          // ── Row navigation ─────────────────────────────────────────────
          _buildRowNavigation(),
        ],
      ),
    );
  }

  Widget _buildLedItem(int index, bool isOn) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // LED hình tròn
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOn
                ? AppTheme.accentYellow
                : const Color(0xFF1E2A38),
            border: Border.all(
              color: isOn
                  ? AppTheme.accentYellow
                  : const Color(0xFF2D3E50),
              width: 1.5,
            ),
            boxShadow: isOn
                ? [
                    BoxShadow(
                      color: AppTheme.accentYellow.withValues(alpha: 0.7),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: isOn
              ? Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 3),
        // Index label
        Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: isOn
                ? AppTheme.accentYellow
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildRowNavigation() {
    return Row(
      children: [
        // Nút hàng trước
        _NavButton(
          icon: Icons.chevron_left,
          onTap: currentRow > 0 ? () => onRowChange(currentRow - 1) : null,
        ),
        const SizedBox(width: 8),

        // Thanh tiến trình hàng
        Expanded(
          child: Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppTheme.accentYellow,
                  inactiveTrackColor: const Color(0xFF2D3E50),
                  thumbColor: AppTheme.accentYellow,
                  overlayColor: AppTheme.accentYellow.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: currentRow.toDouble(),
                  min: 0,
                  max: (matrix.length - 1).toDouble(),
                  divisions: matrix.length > 1 ? matrix.length - 1 : 1,
                  onChanged: (v) => onRowChange(v.round()),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),
        // Nút hàng tiếp
        _NavButton(
          icon: Icons.chevron_right,
          onTap: currentRow < matrix.length - 1
              ? () => onRowChange(currentRow + 1)
              : null,
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NavButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? AppTheme.accentBlue.withValues(alpha: 0.2)
              : const Color(0xFF1E2A38),
          border: Border.all(
            color: enabled
                ? AppTheme.accentBlue
                : const Color(0xFF2D3E50),
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? AppTheme.accentBlue : const Color(0xFF2D3E50),
          size: 20,
        ),
      ),
    );
  }
}
