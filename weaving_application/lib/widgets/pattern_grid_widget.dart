// lib/widgets/pattern_grid_widget.dart
// Grid hiển thị thư viện mẫu — người dùng tap để chọn và render

import 'package:flutter/material.dart';
import '../services/weaving_api_service.dart';
import '../utils/app_theme.dart';

class PatternGridWidget extends StatelessWidget {
  final List<PatternSuggestion> patterns;
  final ValueChanged<PatternSuggestion> onSelect;
  final VoidCallback onUploadImage;

  const PatternGridWidget({
    super.key,
    required this.patterns,
    required this.onSelect,
    required this.onUploadImage,
  });

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
              const Icon(Icons.dashboard_rounded,
                  size: 18, color: AppTheme.accentBlue),
              const SizedBox(width: 6),
              const Text(
                'Thư Viện Mẫu',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const Spacer(),
              // Nút upload ảnh tùy chỉnh
              GestureDetector(
                onTap: onUploadImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppTheme.warmGradient,
                    borderRadius: AppTheme.radiusSM,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upload_rounded,
                          color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Upload ảnh',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Pattern Grid ──────────────────────────────────────────────
          if (patterns.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Nhập mô tả ở trên để tìm mẫu phù hợp',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,      // 3 cột
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.85, // Hơi cao hơn rộng
              ),
              itemCount: patterns.length,
              itemBuilder: (ctx, i) => _PatternCard(
                pattern: patterns[i],
                onTap: () => onSelect(patterns[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  final PatternSuggestion pattern;
  final VoidCallback onTap;

  const _PatternCard({required this.pattern, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusSM,
          color: AppTheme.surfaceBg,
          border: Border.all(
            color: AppTheme.lightBlue.withValues(alpha: 0.3),
          ),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Thumbnail ──────────────────────────────────────────────
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _gradientForIndex(pattern.id),
                  ),
                  child: const Icon(
                    Icons.grid_on,
                    color: Colors.white54,
                    size: 32,
                  ),
                ),
              ),
            ),

            // ── Name + similarity ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pattern.similarity > 0) ...[
                    const SizedBox(height: 2),
                    // Similarity bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pattern.similarity,
                        backgroundColor:
                            AppTheme.textMuted.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(
                          pattern.similarity > 0.7
                              ? AppTheme.success
                              : AppTheme.accentBlue,
                        ),
                        minHeight: 3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _gradientForIndex(String id) {
    // Tạo màu gradient khác nhau cho từng mẫu dựa trên hash của id
    final hash = id.hashCode.abs();
    final gradients = [
      AppTheme.primaryGradient,
      AppTheme.warmGradient,
      AppTheme.coolGradient,
      const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)]),
      const LinearGradient(colors: [Color(0xFF059669), Color(0xFF0EA5E9)]),
    ];
    return gradients[hash % gradients.length];
  }
}
